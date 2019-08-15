extern(C):

import core.stdc.stdio;
import core.stdc.stdarg;
import core.stdc.stdlib;

char* user_input;   // 入力プログラム

void error_at(char* loc, string fmt, ...)
{
    char* cfmt = toStringz(fmt);
    va_list ap;
    va_start(ap, cfmt);

    ptrdiff_t pos = cast(ptrdiff_t)loc - cast(ptrdiff_t)user_input;
    fprintf(stderr, "%s\n", user_input);
    fprintf(stderr, "%*s", cast(int)pos, "".toStringz);
    fprintf(stderr, "^ ");
    vfprintf(stderr, cfmt, ap);
    fprintf(stderr, "\n");
    exit(1);
}


void error(string fmt, ...)
{
    char* cfmt = toStringz(fmt);
    va_list ap;
    va_start(ap, cfmt);
    vfprintf(stderr, cfmt, ap);
    fprintf(stderr, "\n");
    exit(1);
}


char* toStringz(string str)
{
    size_t len = str.length;
    char[] buf = new char[](len+1);
    foreach(i; 0 .. len)
        buf[i] = str[i];

    buf[len] = '\0';
    return buf.ptr;
}
