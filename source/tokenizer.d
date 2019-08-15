extern(C):

import utils;

import core.stdc.ctype;
import core.stdc.stdlib;
import core.stdc.string;

enum TokenKind
{
    RESERVED,    // 記号
    IDENT,
    NUM,         // 整数トークン
    EOF,         // 入力の終わりを表すトークン
}


struct Token
{
    TokenKind kind; // トークンの型
    Token *next;    // 次の入力トークン
    int val;        // kindがTK_NUMの場合，その数値
    char[] str;
}


Token* token;       // 現在着目しているトークン


// 次のトークンが期待している記号のときには，トークンを1つ読み進めて
// 真を返す．それ以外の場合には偽を返す．
bool consume(string op)
{
    if(token.kind != TokenKind.RESERVED || op != token.str)
        return false;

    token = token.next;
    return true;
}


// 次のトークンが期待している記号のときには，トークンを1つ読み進める．
// それ以外の場合にはエラーを報告する．
void expect(string op)
{
    if(token.kind != TokenKind.RESERVED || op != token.str)
        error_at(token.str.ptr, "'%.*s'ではありません", op.length, op.ptr);

    token = token.next;
}


// 次のトークンが数値の場合，トークンを1つ読み進めてその数値を返す．
// それ以外の場合にはエラーを報告する．
int expect_number() {
    if(token.kind != TokenKind.NUM)
        error_at(token.str.ptr, "数ではありません");

    int val = token.val;
    token = token.next;
    return val;
}


bool at_eof()
{
    return token.kind == TokenKind.EOF;
}


Token* consume_ident()
{
    if(token.kind != TokenKind.IDENT)
        return null;

    auto tok = token;
    token = token.next;
    return tok;
}


// 新しいトークンを作成してcurにつなげる
Token* new_token(TokenKind kind, Token* cur, char* str, int len)
{
    Token* tok = new Token;
    tok.kind = kind;
    tok.str = str[0 .. len];
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

        if(*(p+1)) {
            if(p[0 .. 2] == "==" || p[0 .. 2] == "!=" || p[0 .. 2] == "<=" || p[0 .. 2] == ">=") {
                cur = new_token(TokenKind.RESERVED, cur, p, 2);
                p += 2;
                continue;
            }
        }

        if('a' <= *p && *p <= 'z') {
            cur = new_token(TokenKind.IDENT, cur, p, 1);
            ++p;
            continue;
        }

        if(*p == '+' || *p == '-' || *p == '*' || *p == '/' || *p == '(' || *p == ')' || *p == '>' || *p == '<') {
            cur = new_token(TokenKind.RESERVED, cur, p, 1);
            ++p;
            continue;
        }

        if(*p == '=') {
            cur = new_token(TokenKind.RESERVED, cur, p, 1);
            ++p;
            continue;
        }

        if(*p == ';') {
            cur = new_token(TokenKind.RESERVED, cur, p, 1);
            ++p;
            continue;
        }

        if(isdigit(*p)) {
            auto q = p;
            int val = cast(int) strtol(q, &q, 10);
            cur = new_token(TokenKind.NUM, cur, p, cast(int)(q - p));
            cur.val = val;
            p = q;
            continue;
        }

        error_at(p, "トークナイズできません");
    }

    new_token(TokenKind.EOF, cur, p, 0);
    return head.next;
}