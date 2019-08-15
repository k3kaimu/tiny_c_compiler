extern(C):

import tokenizer;
import utils;

enum NodeKind
{
    ADD = 1,    // +
    SUB,        // -
    MUL,        // *
    DIV,        // /
    EQ,         // ==
    NE,         // !=
    LT,         // <
    LE,         // <=
    GT,         // >
    GE,         // >=
    ASSIGN,     // =
    LVAR,       // ローカル変数
    NUM,        // 整数
    FUNC_CALL,  // 関数呼び出し
    EXPR_STMT,  // 式文
    BLOCK,      // block { stmt* }
    RETURN,     // return
    IF,         // if
    IFELSE,     // if-else
    FOR,        // for, while
    BREAK,      // break
    FUNC_DEF,   // 関数定義
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

    // for(init_expr; cond; update_expr) thenblock
    Node* init_expr;
    Node* update_expr;

    // block { stmt* }
    Node*[] stmts;

    Node*[] func_call_args;   // kindがFUNC_CALLのときのみ使う

    // func(args) func_body
    Token*[] func_def_args;
    Node*[] func_def_body;
}



Node* new_node(NodeKind kind, Node* lhs, Node* rhs)
{
    Node* node = new Node;

    node.kind = kind;
    node.lhs = lhs;
    node.rhs = rhs;

    return node;
}


Node* new_node_num(int val)
{
    Node* node = new Node;

    node.kind = NodeKind.NUM;
    node.val = val;

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


// func_def = iden "(" (iden ("," iden)* ","?)? ")" "{" stmt* "}"
Node* func_def()
{
    Node* node = new Node;
    node.kind = NodeKind.FUNC_DEF;

    Token* func_name = consume_ident();
    if(func_name is null)
        error("関数定義ではありません");

    node.token = func_name;

    expect("(");
    if(consume_reserved(")"))
        goto Lbody;

    node.func_def_args ~= consume_ident();
    if(node.func_def_args[0] is null)
        error("関数%.*sの第1引数は識別子ではありません", func_name.str.length, func_name.str.ptr);

    while(!consume_reserved(")")) {
        expect(",");
        if(consume_reserved(")"))
            break;

        node.func_def_args ~= consume_ident();
        if(node.func_def_args[$-1] is null)
            error("関数%.*sの第%d引数は識別子ではありません", func_name.str.length, func_name.str.ptr, node.func_def_args.length);
    }

  Lbody:
    expect("{");
    while(!consume_reserved("}"))
        node.func_def_body ~= stmt();

    return node;
}


// stmt = expr ";"
//      | "{" stmt* "}"
//      | "return" expr ";"
//      | "break" ";"
//      | "if" "(" expr ")" stmt ("else" stmt)?
//      | "for" "(" expr? ";" expr? ";" expr? ")" stmt
//      | "while" "(" expr ")" stmt
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
        if(!consume_reserved(";")) {
            node.init_expr = expr();
            expect(";");
        }

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
            node.cond = new_node_num(1);

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

    if(consume(TokenKind.BREAK)) {
        expect(";");
        Node* node = new Node;
        node.kind = NodeKind.BREAK;
        return node;
    }

    Node* node;
    if(consume(TokenKind.RETURN)) {
        node = new Node;
        node.kind = NodeKind.RETURN;
        node.lhs = expr();
    } else {
        node = new Node;
        node.kind = NodeKind.EXPR_STMT;
        node.lhs = expr();
    }

    expect(";");
    return node;
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


// mul  = unary ("*" unary | "/" unary)*
Node* mul()
{
    Node* node = unary();

    while(1) {
        if(consume_reserved("*"))
            node = new_node(NodeKind.MUL, node, unary());
        else if(consume_reserved("/"))
            node = new_node(NodeKind.DIV, node, unary());
        else
            return node;
    }
}


// unary = ("+" | "-")? term
Node* unary()
{
    if(consume_reserved("+"))
        return term;
    else if(consume_reserved("-"))
        return new_node(NodeKind.SUB, new_node_num(0), term());
    else
        return term();
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
            Node* node = new Node;
            node.kind = NodeKind.LVAR;
            node.token = tok;
            return node;
        }
    }

    return new_node_num(expect_number());
}
