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
    NUM,        // 整数
}


struct Node
{
    NodeKind kind;
    Node* lhs;
    Node* rhs;
    int val;    //  kindがNUMのときのみ使う
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


// expr = equality
Node* expr()
{
    Node* node = equality();
    return node;
}


// equality = relational ("==" relational | "!=" relational)*
Node* equality()
{
    Node* node = relational();

    while(1) {
        if(consume("=="))
            node = new_node(NodeKind.EQ, node, relational());
        else if(consume("!="))
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
        if(consume("<"))
            node = new_node(NodeKind.LT, node, add());
        else if(consume("<="))
            node = new_node(NodeKind.LE, node, add());
        else if(consume(">"))
            node = new_node(NodeKind.GT, node, add());
        else if(consume(">="))
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
        if(consume("+"))
            node = new_node(NodeKind.ADD, node, mul());
        else if(consume("-"))
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
        if(consume("*"))
            node = new_node(NodeKind.MUL, node, unary());
        else if(consume("/"))
            node = new_node(NodeKind.DIV, node, unary());
        else
            return node;
    }
}


// unary = ("+" | "-")? term
Node* unary()
{
    if(consume("+"))
        return term;
    else if(consume("-"))
        return new_node(NodeKind.SUB, new_node_num(0), term());
    else
        return term();
}


// term = num | "(" expr ")"
Node* term()
{
    if(consume("(")) {
        Node* node = expr();
        expect(")");
        return node;
    }

    return new_node_num(expect_number());
}
