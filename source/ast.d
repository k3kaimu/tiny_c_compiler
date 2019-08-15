extern(C):

import tokenizer;

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
    EXPR_STMT,  // 式文
    BLOCK,      // block { stmt* }
    RETURN,     // return
    IF,         // if
    IFELSE,     // if-else
    FOR,        // for
    BREAK,      // break
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


// program = stmt*
Node*[] program()
{
    Node*[] nodes;
    int i = 0;
    while(!at_eof())
        nodes ~= stmt();

    return nodes;
}


// stmt = expr ";"
//      | "{" stmt* "}"
//      | "return" expr ";"
//      | "break" ";"
//      | "if" "(" expr ")" stmt ("else" stmt)?
//      | "for" "(" expr? ";" expr? ";" expr? ")" stmt
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


// term = num | iden | "(" expr ")"
Node* term()
{
    if(consume_reserved("(")) {
        Node* node = expr();
        expect(")");
        return node;
    }

    if(Token* tok = consume_ident()) {
        Node* node = new Node;
        node.kind = NodeKind.LVAR;
        node.token = tok;
        return node;
    }

    return new_node_num(expect_number());
}
