extern(C):

import tokenizer;

enum NodeKind
{
    ADD = 1,    // +
    SUB,        // -
    MUL,        // *
    DIV,        // /
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


// expr = mul ("+" mul | "-" mul)*
Node* expr()
{
    Node* node = mul();

    while(1) {
        if(consume('+'))
            node = new_node(NodeKind.ADD, node, mul());
        else if(consume('-'))
            node = new_node(NodeKind.SUB, node, mul());
        else
            return node;
    }
}


// mul  = term ("*" term | "/" term)*
Node* mul()
{
    Node* node = term();

    while(1) {
        if(consume('*'))
            node = new_node(NodeKind.MUL, node, term());
        else if(consume('/'))
            node = new_node(NodeKind.DIV, node, term());
        else
            return node;
    }
}


// term = num | "(" expr ")"
Node* term()
{
    if(consume('(')) {
        Node* node = expr();
        expect(')');
        return node;
    }

    return new_node_num(expect_number());
}
