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
    RETURN,     // return
}


struct Node
{
    NodeKind kind;
    Node* lhs;
    Node* rhs;
    int val;        // kindがNUMのときのみ使う
    Token* token;   // kindがIDENTのときのみ使う
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


// stmt = expr ";" | "return" expr ";"
Node* stmt()
{
    Node* node;
    if(consume(TokenKind.RETURN)) {
        node = new Node;
        node.kind = NodeKind.RETURN;
        node.lhs = expr();
    } else {
        node = expr();
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
