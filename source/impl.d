extern(C):

import core.stdc.stdio;
import core.stdc.stdlib;

int Main(FILE* fp, int argc, char** argv)
{
    if(argc != 2) {
        fprintf(stderr, "引数の個数が正しくありません\n");
        return 1;
    }

    char* p = argv[1];

    fprintf(fp, "define i32 @main() {\n");
    fprintf(fp, "    %%1 = add i32 0, %lld\n", strtol(p, &p, 10));

    int cnt = 1;
    while(*p) {
        if(*p == '+') {
            ++p;
            fprintf(fp, "    %%%d = add i32 %%%d, %ld\n", cnt+1, cnt, strtol(p, &p, 10));
            ++cnt;
            continue;
        }

        if(*p == '-') {
            ++p;
            fprintf(fp, "    %%%d = sub i32 %%%d, %ld\n", cnt+1, cnt, strtol(p, &p, 10));
            ++cnt;
            continue;
        }

        fprintf(stderr, "予期しない文字です: '%c'\n", *p);
        return 1;
    }

    fprintf(fp, "  ret i32 %%%d\n", cnt);
    fprintf(fp, "}\n");

    return 0;
}
