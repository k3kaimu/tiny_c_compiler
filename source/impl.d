extern(C):

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.stdarg;
import core.stdc.ctype;


private
char* toStringz(string str)
{
    size_t len = str.length;
    char* buf = cast(char*) calloc(1, len + 1);
    foreach(i; 0 .. len)
        buf[i] = str[i];

    return buf;
}


char* user_input;   // 入力プログラム


void error(char* loc, string fmt, ...) {
    char* cfmt = toStringz(fmt);
    va_list ap;
    va_start(ap, cfmt);

    ptrdiff_t pos = cast(ptrdiff_t)loc - cast(ptrdiff_t)user_input;
    {
        import std.stdio;
        import std;
        writeln(pos);
        enforce(pos >= 0);
        // return;
    }
    fprintf(stderr, "%s\n", user_input);
    fprintf(stderr, "%*s", cast(int)pos, "".toStringz);
    fprintf(stderr, "^ ");
    vfprintf(stderr, cfmt, ap);
    fprintf(stderr, "\n");
    exit(1);
}


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
    Token* tok = cast(Token*) calloc(1, Token.sizeof);
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


int Main(FILE* fp, int argc, char** argv)
{
    if(argc != 2) {
        fprintf(stderr, "引数の個数が正しくありません\n");
        return 1;
    }

    user_input = argv[1];
    token = tokenize(argv[1]);

    fprintf(fp, "define i32 @main() {\n");
    fprintf(fp, "  %%1 = add i32 0, %d\n", expect_number());

    int cnt = 1;
    while(!at_eof()) {
        if(consume('+')) {
            fprintf(fp, "  %%%d = add i32 %%%d, %d\n", cnt+1, cnt, expect_number());
            ++cnt;
            continue;
        }

        expect('-');
        fprintf(fp, "  %%%d = sub i32 %%%d, %d\n", cnt+1, cnt, expect_number());
        ++cnt;
    }

    fprintf(fp, "  ret i32 %%%d\n", cnt);
    fprintf(fp, "}\n");

    return 0;
}
