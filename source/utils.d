extern(C):

import core.stdc.stdio;
import core.stdc.stdarg;
import core.stdc.stdlib;

char* user_input;   // 入力プログラム

bool ignore_error = false;

void error_at(char* loc, string fmt, ...)
{
    if(!ignore_error) {
        char* cfmt = toStringz(fmt);
        va_list ap;
        va_start(ap, cfmt);

        ptrdiff_t pos = cast(ptrdiff_t)loc - cast(ptrdiff_t)user_input;
        fprintf(stderr, "%s\n", user_input);
        fprintf(stderr, "%*s", cast(int)pos, "".toStringz);
        fprintf(stderr, "^ ");
        vfprintf(stderr, cfmt, ap);
        fprintf(stderr, "\n");
        // exit(1);
        throw new Exception("");
    }
}


void error(string fmt, ...)
{
    if(!ignore_error) {
        char* cfmt = toStringz(fmt);
        va_list ap;
        va_start(ap, cfmt);
        vfprintf(stderr, cfmt, ap);
        fprintf(stderr, "\n");
        // exit(1);
        throw new Exception("");
    }
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
