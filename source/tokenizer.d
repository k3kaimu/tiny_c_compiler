extern(C):

import utils;

import core.stdc.ctype;
import core.stdc.stdlib;
import core.stdc.string;

enum TokenKind
{
    RESERVED,       // 記号
    RETURN,         // return
    IF,             // if
    ELSE,           // else
    FOR,            // for
    WHILE,          // while
    BREAK,          // break
    FOREACH,        // foreach
    AUTO,           // auto
    VOID,           // void
    BOOL,           // bool
    CHAR,           // char
    BYTE,           // byte
    SHORT,          // short
    INT,            // int
    LONG,           // long
    CAST,           // cast
    PTR,            // Ptr
    TYPENAME,       // Typename
    EXTERN_C,       // extern(C)
    IDENT,          // 識別子
    NUM,            // 整数トークン
    STR_LIT,        // 文字列リテラル
    EOF,            // 入力の終わりを表すトークン
}


struct Token
{
    TokenKind kind; // トークンの型
    Token *next;    // 次の入力トークン
    int val;        // kindがTK_NUMの場合，その数値
    const(char)[] str;
    const(ubyte)[] str_lit_data;
}


Token* token;       // 現在着目しているトークン


Token* save_tokenizer()
{
    return token;
}


void restore_tokenizer(Token* new_head)
{
    token = new_head;
}


Token* pop_token()
{
    Token* ret = token;
    token = token.next;
    return ret;
}


// 次のトークンが期待している記号のときには，トークンを1つ読み進めて
// 真を返す．それ以外の場合には偽を返す．
bool consume_reserved(string op)
{
    if(token.kind != TokenKind.RESERVED || op != token.str)
        return false;

    token = token.next;
    return true;
}


bool consume(TokenKind kind)
{
    if(token.kind != kind)
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
Token* new_token(TokenKind kind, Token* cur, char[] str)
{
    Token* tok = new Token;
    tok.kind = kind;
    tok.str = str;
    cur.next = tok;
    return tok;
}


Token* tokenize(char[] str)
{
    Token head;
    head.next = null;
    Token* cur = &head;

    while(str.length) {
        // 空白文字をスキップ
        if(isspace(str[0])) {
            str = str[1 .. $];
            continue;
        }

        // return
        if(size_t len = starts_with_reserved(str, "return")) {
            cur = new_token(TokenKind.RETURN, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        // if
        if(size_t len = starts_with_reserved(str, "if")) {
            cur = new_token(TokenKind.IF, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        // else
        if(size_t len = starts_with_reserved(str, "else")) {
            cur = new_token(TokenKind.ELSE, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "for")) {
            cur = new_token(TokenKind.FOR, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "while")) {
            cur = new_token(TokenKind.WHILE, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "break")) {
            cur = new_token(TokenKind.BREAK, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "foreach")) {
            cur = new_token(TokenKind.FOREACH, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "auto")) {
            cur = new_token(TokenKind.AUTO, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "void")) {
            cur = new_token(TokenKind.VOID, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "bool")) {
            cur = new_token(TokenKind.BOOL, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "char")) {
            cur = new_token(TokenKind.CHAR, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "byte")) {
            cur = new_token(TokenKind.BYTE, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "short")) {
            cur = new_token(TokenKind.SHORT, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "int")) {
            cur = new_token(TokenKind.INT, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "long")) {
            cur = new_token(TokenKind.LONG, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "cast")) {
            cur = new_token(TokenKind.CAST, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "Ptr")) {
            cur = new_token(TokenKind.PTR, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "Typename")) {
            cur = new_token(TokenKind.TYPENAME, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(size_t len = starts_with_reserved(str, "extern(C)")) {
            cur = new_token(TokenKind.EXTERN_C, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if(str.length >= 3 && str[0 .. 3] == "...") {
            cur = new_token(TokenKind.RESERVED, cur, str[0 .. 3]);
            str = str[3 .. $];
            continue;
        }

        if(str.length >= 2) {
            if( str[0 .. 2] == "==" || str[0 .. 2] == "!="
             || str[0 .. 2] == "<=" || str[0 .. 2] == ">="
             || str[0 .. 2] == ".."
             || str[0 .. 2] == "++" || str[0 .. 2] == "--"
             || str[0 .. 2] == "||" || str[0 .. 2] == "&&"
            )
            {
                cur = new_token(TokenKind.RESERVED, cur, str[0 .. 2]);
                str = str[2 .. $];
                continue;
            }
        }

        if(isalpha(str[0]) || str[0] == '_') {
            size_t len = 0;
            {
                char[] q = str;
                while(is_iden_char(q[0])) {
                    ++len;
                    q = q[1 .. $];
                }
            }
            cur = new_token(TokenKind.IDENT, cur, str[0 .. len]);
            str = str[len .. $];
            continue;
        }

        if( str[0] == '+' || str[0] == '-' || str[0] == '*' || str[0] == '/' || str[0] == '%'
         || str[0] == '(' || str[0] == ')' || str[0] == '>' || str[0] == '<' || str[0] == '&'
         || str[0] == '!') {
            cur = new_token(TokenKind.RESERVED, cur, str[0 .. 1]);
            str = str[1 .. $];
            continue;
        }

        if(str[0] == '{' || str[0] == '}' || str[0] == '[' || str[0] == ']') {
            cur = new_token(TokenKind.RESERVED, cur, str[0 .. 1]);
            str = str[1 .. $];
            continue;
        }

        if(str[0] == '=') {
            cur = new_token(TokenKind.RESERVED, cur, str[0 .. 1]);
            str = str[1 .. $];
            continue;
        }

        if(str[0] == ';' || str[0] == ',' || str[0] == '.') {
            cur = new_token(TokenKind.RESERVED, cur, str[0 .. 1]);
            str = str[1 .. $];
            continue;
        }

        if(isdigit(str[0])) {
            size_t lit_len;
            int val = get_int_literal_value(str, lit_len);
            cur = new_token(TokenKind.NUM, cur, str[0 .. lit_len]);
            cur.val = val;
            str = str[lit_len .. $];
            continue;
        }

        if(str[0] == '"') {
            size_t lit_len;
            ubyte[] data = get_string_literal_value(str, lit_len);
            cur = new_token(TokenKind.STR_LIT, cur, str[0 .. lit_len]);
            cur.str_lit_data = data;
            str = str[lit_len .. $];
            continue;
        }

        error_at(str.ptr, "トークナイズできません");
    }

    new_token(TokenKind.EOF, cur, str[$ .. $]);
    return head.next;
}


// 文字列の先頭が予約語で始まっているか？
size_t starts_with_reserved(const(char)[] str, string reserved)
{
    if(str.length < reserved.length) return false;
    if(str == reserved) return true;
    if(str[0 .. reserved.length] != reserved)
        return false;

    auto rem = str[reserved.length .. $];
    if(is_iden_char(rem[0]))
        return 0;
    else
        return reserved.length;
}


bool is_iden_char(char c)
{
    return isalnum(c) || c == '_';
}


int get_int_literal_value(const(char)[] str, ref size_t len)
{
    len = 0;
    int val = 0;
    while(str.length && isdigit(str[0])) {
        ++len;
        val *= 10;
        val += (str[0] - '0');
        str = str[1 .. $];
    }

    if(len == 0)
        error("数値リテラルではありません");

    return val;
}

unittest
{
    size_t len;
    string s = "123 ";
    assert(get_int_literal_value(s, len) == 123);
    assert(s[len .. $] == " ");
    s = "1_ 123";
    assert(get_int_literal_value(s, len) == 1);
    assert(s[len .. $] == "_ 123");
}


ubyte[] get_string_literal_value(const(char)[] str, ref size_t len)
{
    assert(str[0] == '"');
    assert(str.length >= 2);

    ubyte[] data;
    size_t i = 1;
    while(str[i] != '"') {
        if(str[i] == '\\') {
            if(str.length == i) goto Lerror;
            ++i;
            switch(str[i]) {
                case 'a': data ~= '\a'; break;
                case 'b': data ~= '\b'; break;
                case 'f': data ~= '\f'; break;
                case 'n': data ~= '\n'; break;
                case 'r': data ~= '\r'; break;
                case 't': data ~= '\t'; break;
                case 'v': data ~= '\v'; break;
                case '0': data ~= '\0'; break;
                default: data ~= str[i];
            }
        } else {
            data ~= str[i];
        }

        ++i;
        continue;

     Lerror:
        error_at(str.ptr, "文字列リテラルが終わっていません");
    }

    len = i + 1;
    data ~= '\0';

    return data;
}

unittest
{
    size_t len;
    ubyte[] data;
    data = get_string_literal_value(q{"1234567890"}, len);
    assert(len == 12);
    assert(data == cast(ubyte[])"1234567890\0");

    data = get_string_literal_value(q{"\a\b"}, len);
    assert(len == 6);
    assert(data == ['\a', '\b', '\0']);

    data = get_string_literal_value(q{"\"\'\n \0"}, len);
    assert(len == 11);
    assert(data == ['\"', '\'', '\n', ' ', '\0', '\0']);
}
