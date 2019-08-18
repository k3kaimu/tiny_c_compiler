extern(C):

import tokenizer;
import utils;
import typesys;

enum NodeKind
{
    ADD = 1,    // +
    SUB,        // -
    MUL,        // *
    DIV,        // /
    REM,        // %
    EQ,         // ==
    NE,         // !=
    LT,         // <
    LE,         // <=
    GT,         // >
    GE,         // >=
    ASSIGN,     // =
    DOT,        // .
    PRE_INC,    // ++
    PRE_DEC,    // --
    POST_INC,   // ++
    POST_DEC,   // --
    CAST,       // キャスト
    LVAR,       // ローカル変数
    NUM,        // 整数
    FUNC_CALL,  // 関数呼び出し
    EXPR_STMT,  // 式文
    BLOCK,      // block { stmt* }
    RETURN,     // return
    IF,         // if
    IFELSE,     // if-else
    FOR,        // for, while
    FOREACH,    // foreach
    BREAK,      // break
    FUNC_DEF,   // 関数定義
    TYPE,       // 型
    LVAR_DEF,   // ローカル変数定義
}


struct Variable
{
    Type* type;
    Token* token;
}


struct Node
{
    NodeKind kind;
    Node* lhs;
    Node* rhs;
    int val;        // kindがNUMのときのみ使う
    Token* token;   // kindがIDENTのときのみ使う

    // if, if-else
    Node* cond;
    Node* thenblock;
    Node* elseblock;

    // for(init_stmt; cond; update_expr) thenblock
    Node* init_stmt;
    Node* update_expr;

    // foreach(def_loop_var; start .. end) thenblock
    Node* def_loop_var;
    Node* start_expr;
    Node* end_expr;

    // block { stmt* }
    Node*[] stmts;

    Node*[] func_call_args;   // kindがFUNC_CALLのときのみ使う

    // ret_type token.str(func_def_args) func_def_body
    Type* ret_type;
    Variable[] func_def_args;
    Node*[] func_def_body;

    Type* type;                 // TYPE か exprのときのみ使う
    Variable def_var;           // kindがLVAR_DEFのときのみ使う
}



Node* new_node(NodeKind kind, Node* lhs, Node* rhs)
{
    Node* node = new Node;

    node.kind = kind;
    node.lhs = lhs;
    node.rhs = rhs;

    return node;
}


Node* new_node_num(Token* tk, int val)
{
    Node* node = new Node;

    node.kind = NodeKind.NUM;
    node.val = val;
    node.token = tk;

    return node;
}


Node* new_node_cast(Type* toType, Node* from)
{
    Node* node = new Node;

    node.kind = NodeKind.CAST;
    node.lhs = from;
    node.type = toType;

    return node;
}


// program = func_def*
Node*[] program()
{
    Node*[] nodes;
    int i = 0;
    while(!at_eof())
        nodes ~= func_def();

    return nodes;
}


// func_def = type iden "(" (type iden ("," type iden)* ","?)? ")" "{" stmt* "}"
Node* func_def()
{
    Node* node = new Node;
    node.kind = NodeKind.FUNC_DEF;
    node.ret_type = type().type;
    Token* func_name = consume_ident();
    if(func_name is null) {
        error("関数定義ではありません");
        return null;
    }

    node.token = func_name;

    Type* arg_type;
    Token* arg_ident;

    expect("(");
    if(consume_reserved(")"))
        goto Lbody;

    arg_type = type().type;
    arg_ident = consume_ident();
    if(arg_ident is null) {
        error("関数%.*sの第1引数は識別子ではありません", func_name.str.length, func_name.str.ptr);
        return null;
    }

    node.func_def_args ~= Variable(arg_type, arg_ident);

    while(!consume_reserved(")")) {
        expect(",");
        if(consume_reserved(")"))
            break;

        arg_type = type().type;
        arg_ident = consume_ident();
        if(arg_ident is null) {
            error("関数%.*sの第%d引数は識別子ではありません", func_name.str.length, func_name.str.ptr, node.func_def_args.length + 1);
            return null;
        }

        node.func_def_args ~= Variable(arg_type, arg_ident);
    }

  Lbody:
    expect("{");
    while(!consume_reserved("}"))
        node.func_def_body ~= stmt();

    return node;
}


// expr_stmt_or_def_var
//      = expr ";"
//      | type ident ("=" expr)? ";"
Node* expr_stmt_or_def_var()
{
    // まず式文かどうか試す
    ignore_error = true;
    auto saved_tokenizer_state = save_tokenizer();
    if(expr() !is null && consume_reserved(";")) {
        // 式文
        ignore_error = false;
        restore_tokenizer(saved_tokenizer_state);

        Node* node = new Node;
        node.kind = NodeKind.EXPR_STMT;
        node.lhs = expr();
        expect(";");
        return node;
    }

    ignore_error = false;
    restore_tokenizer(saved_tokenizer_state);

    // 変数定義
    {
        Node* node = new Node;
        node.kind = NodeKind.LVAR_DEF;
        node.def_var.type = type().type;
        node.def_var.token = consume_ident();
        node.token = node.def_var.token;
        assert(node.def_var.type !is null);
        assert(node.def_var.token !is null);

        if(consume_reserved("=")) {
            node.lhs = expr();
        }

        expect(";");
        return node;
    }

    return null;
}

// def_var = type ident ";"
Node* def_var()
{
    Node* node = new Node;
    node.kind = NodeKind.LVAR_DEF;
    node.def_var.type = type().type;
    node.def_var.token = consume_ident();
    node.token = node.def_var.token;
    expect(";");
    assert(node.def_var.type !is null);
    assert(node.def_var.token !is null);
    return node;
}


// stmt = "{" stmt* "}"
//      | "return" expr ";"
//      | "break" ";"
//      | "if" "(" expr ")" stmt ("else" stmt)?
//      | "for" "(" (expr_stmt_or_def_var | ";") expr? ";" expr? ")" stmt
//      | "while" "(" expr ")" stmt
//      | "foreach" "(" def_var ";" expr ".." expr ")" stmt
//      | expr_stmt_of_def_var
Node* stmt()
{
    if(consume_reserved("{")) {
        Node*[] stmts;
        while(1) {
            if(consume_reserved("}"))
                break;

            stmts ~= stmt();
        }

        Node* node = new Node;
        node.kind = NodeKind.BLOCK;
        node.stmts = stmts;
        return node;
    }

    if(consume(TokenKind.IF)) {
        expect("(");
        Node* node = new Node;
        node.kind = NodeKind.IF;
        node.cond = expr();
        expect(")");
        node.thenblock = stmt();
        if(consume(TokenKind.ELSE)) {
            node.kind = NodeKind.IFELSE;
            node.elseblock = stmt();
        }

        return node;
    }

    if(consume(TokenKind.FOR)) {
        expect("(");
        Node* node = new Node;
        node.kind = NodeKind.FOR;
        if(!consume_reserved(";"))
            node.init_stmt = expr_stmt_or_def_var();

        if(!consume_reserved(";")) {
            node.cond = expr();
            expect(";");
        }

        if(!consume_reserved(")")) {
            node.update_expr = expr();
            expect(")");
        }

        node.thenblock = stmt();

        if(node.cond is null)
            node.cond = new_node_num(null, 1);

        return node;
    }

    if(consume(TokenKind.WHILE)) {
        Node* node = new Node;
        node.kind = NodeKind.FOR;
        expect("(");
        node.cond = expr();
        expect(")");
        node.thenblock = stmt();
        return node;
    }

    if(consume(TokenKind.FOREACH)) {
        expect("(");
        Node* def = def_var();
        Node* start_expr = expr();
        expect("..");
        Node* end_expr = expr();
        expect(")");
        Node* body_ = stmt();

        Node* node = new Node;
        node.kind = NodeKind.FOREACH;
        node.def_loop_var = def;
        node.start_expr = start_expr;
        node.end_expr = end_expr;
        node.thenblock = body_;
        return node;
    }

    if(consume(TokenKind.BREAK)) {
        expect(";");
        Node* node = new Node;
        node.kind = NodeKind.BREAK;
        return node;
    }

    if(consume(TokenKind.RETURN)) {
        Node* node = new Node;
        node.kind = NodeKind.RETURN;
        node.lhs = expr();
        expect(";");
        return node;
    }

    return expr_stmt_or_def_var();
}


// expr = assign
Node* expr()
{
    Node* node = assign();
    return node;
}


// assign = equality ("=" assign)?
Node* assign()
{
    Node* node = equality();
    if(consume_reserved("="))
        node = new_node(NodeKind.ASSIGN, node, assign());

    return node;
}


// equality = relational ("==" relational | "!=" relational)*
Node* equality()
{
    Node* node = relational();

    while(1) {
        if(consume_reserved("=="))
            node = new_node(NodeKind.EQ, node, relational());
        else if(consume_reserved("!="))
            node = new_node(NodeKind.NE, node, relational());
        else
            return node;
    }
}


// relational = add ("<" add | "<=" add | ">" add | ">=" add)*
Node* relational()
{
    Node* node = add();

    while(1) {
        if(consume_reserved("<"))
            node = new_node(NodeKind.LT, node, add());
        else if(consume_reserved("<="))
            node = new_node(NodeKind.LE, node, add());
        else if(consume_reserved(">"))
            node = new_node(NodeKind.GT, node, add());
        else if(consume_reserved(">="))
            node = new_node(NodeKind.GE, node, add());
        else
            return node;
    }
}


// add = mul ("+" mul | "-" mul)*
Node* add()
{
    Node* node = mul();

    while(1) {
        if(consume_reserved("+"))
            node = new_node(NodeKind.ADD, node, mul());
        else if(consume_reserved("-"))
            node = new_node(NodeKind.SUB, node, mul());
        else
            return node;
    }
}


// mul  = unary ("*" unary | "/" unary | "%" unary)*
Node* mul()
{
    Node* node = unary();

    while(1) {
        if(consume_reserved("*"))
            node = new_node(NodeKind.MUL, node, unary());
        else if(consume_reserved("/"))
            node = new_node(NodeKind.DIV, node, unary());
        else if(consume_reserved("%"))
            node = new_node(NodeKind.REM, node, unary());
        else
            return node;
    }
}


// unary = ("+" | "-")? unary
//       | ("++" | "--")? unary
//       | "cast" "(" type ")" unary
Node* unary()
{
    auto tk = token;

    if(consume_reserved("++"))
    {
        Node* node = new Node;
        node.token = tk;
        node.kind = NodeKind.PRE_INC;
        node.lhs = unary();
        return node;
    }
    else if(consume_reserved("--"))
    {
        Node* node = new Node;
        node.token = tk;
        node.kind = NodeKind.PRE_DEC;
        node.lhs = unary();
        return node;
    }
    else if(consume_reserved("+"))
        return unary();
    else if(consume_reserved("-"))
        return new_node(NodeKind.SUB, new_node_num(null, 0), unary());
    else if(consume(TokenKind.CAST)) {
        expect("(");
        Type* ty = type().type;
        expect(")");
        Node* node = unary();

        return new_node_cast(ty, node);
    } else
        return postfix();
}


// postfix = term
//         | postfix "++"
//         | postfix "--"
//         | postfix "." ident
Node* postfix()
{
    Node* lhs = term();

    while(1) {
        Token* tk = token;

        if(consume_reserved("++")) {
            Node* new_node = new Node;
            new_node.token = tk;
            new_node.kind = NodeKind.POST_INC;
            new_node.lhs = lhs;
            lhs = new_node;
            continue;
        }

        if(consume_reserved("--")) {
            Node* new_node = new Node;
            new_node.token = tk;
            new_node.kind = NodeKind.POST_DEC;
            new_node.lhs = lhs;
            lhs = new_node;
            continue;
        }

        if(consume_reserved(".")) {
            Node* new_node = new Node;
            new_node.token = tk;
            new_node.kind = NodeKind.DOT;
            new_node.token = consume_ident();
            new_node.lhs = lhs;
            lhs = new_node;

            if(new_node.token is null) {
                error_at(tk.str.ptr, "メンバアクセス演算子 '.' の後続に識別子がありません");
                return null;
            }
            continue;
        }
        return lhs;
    }

    return lhs;
}


// term = num
//      | iden ( "("  ")" )?
//      | iden "(" expr ("," expr)* ","? ")"
//      | "(" expr ")"
Node* term()
{
    if(consume_reserved("(")) {
        Node* node = expr();
        expect(")");
        return node;
    }

    if(Token* tok = consume_ident()) {
        if(consume_reserved("(")) {
            // 関数呼び出し
            Node* node = new Node;
            node.kind = NodeKind.FUNC_CALL;
            node.token = tok;

            if(consume_reserved(")"))
                return node;

            node.func_call_args ~= expr();

            while(!consume_reserved(")")) {
                expect(",");
                if(consume_reserved(")"))
                    break;

                node.func_call_args ~= expr();
            }

            return node;
        } else {
            // 変数
            return new_node_lvar(tok);
        }
    }

    return new_node_num(token, expect_number());
}


Node* new_node_lvar(Token* ident)
{
    Node* node = new Node;
    node.kind = NodeKind.LVAR;
    node.token = ident;
    return node;
}


// type = basic_type "*"*
//      | auto
Node* type()
{
    Node* node = new Node;
    node.kind = NodeKind.TYPE;

    if(consume(TokenKind.AUTO)) {
        Type* ty = new Type;
        ty.kind = TypeKind.BASE;
        ty.islval = false;
        ty.str = "auto";
        ty.nested = null;
        node.type = ty;
        return node;
    }

    Type* ty = basic_type();
    while(consume_reserved("*")) {
        Type* new_ty = new Type;
        new_ty.kind = TypeKind.POINTER;
        new_ty.str = ty.str ~ "*";
        new_ty.nested = ty;
        ty = new_ty;
    }

    node.type = ty;
    return node;
}


// basic_type = char | byte | short | int | long | ident
Type* basic_type()
{
    Type* ty = new Type;
    ty.kind = TypeKind.BASE;

    if(consume(TokenKind.BOOL)) {
        ty.str = "bool";
        return ty;
    }

    if(consume(TokenKind.CHAR)) {
        ty.str = "char";
        return ty;
    }

    if(consume(TokenKind.BYTE)) {
        ty.str = "byte";
        return ty;
    }

    if(consume(TokenKind.SHORT)) {
        ty.str = "short";
        return ty;
    }

    if(consume(TokenKind.INT)) {
        ty.str = "int";
        return ty;
    }

    if(consume(TokenKind.LONG)) {
        ty.str = "long";
        return ty;
    }

    if(Token* tok = consume_ident()) {
        ty.str = tok.str;
        return ty;
    }

    error_at(token.str.ptr, "型ではありません");
    return null;
}
