extern(C):

import utils;

import core.stdc.ctype;
import core.stdc.stdlib;

enum TokenKind
{
    RESERVED,    // 記号
    NUM,         // 整数トークン
    EOF,         // 入力の終わりを表すトークン
}


struct Token
{
    TokenKind kind; // トークンの型
    Token *next;    // 次の入力トークン
    int val;        // kindがTK_NUMの場合，その数値
    char* str;      // トークン文字列
}


Token* token;       // 現在着目しているトークン


// 次のトークンが期待している記号のときには，トークンを1つ読み進めて
// 真を返す．それ以外の場合には偽を返す．
bool consume(char op)
{
    if(token.kind != TokenKind.RESERVED || token.str[0] != op)
        return false;

    token = token.next;
    return true;
}


// 次のトークンが期待している記号のときには，トークンを1つ読み進める．
// それ以外の場合にはエラーを報告する．
void expect(char op)
{
    if(token.kind != TokenKind.RESERVED || token.str[0] != op)
        error(token.str, "'%c'ではありません", op);

    token = token.next;
}


// 次のトークンが数値の場合，トークンを1つ読み進めてその数値を返す．
// それ以外の場合にはエラーを報告する．
int expect_number() {
    if(token.kind != TokenKind.NUM)
        error(token.str, "数ではありません");

    int val = token.val;
    token = token.next;
    return val;
}


bool at_eof()
{
    return token.kind == TokenKind.EOF;
}


// 新しいトークンを作成してcurにつなげる
Token* new_token(TokenKind kind, Token* cur, char* str)
{
    Token* tok = new Token;
    tok.kind = kind;
    tok.str = str;
    cur.next = tok;
    return tok;
}


Token* tokenize(char* p)
{
    Token head;
    head.next = null;
    Token* cur = &head;

    while(*p) {
        // 空白文字をスキップ
        if(isspace(*p)) {
            ++p;
            continue;
        }

        if(*p == '+' || *p == '-') {
            cur = new_token(TokenKind.RESERVED, cur, p);
            ++p;
            continue;
        }

        if(isdigit(*p)) {
            cur = new_token(TokenKind.NUM, cur, p);
            cur.val = cast(int) strtol(p, &p, 10);
            continue;
        }

        error(p, "トークナイズできません");
    }

    new_token(TokenKind.EOF, cur, p);
    return head.next;
}