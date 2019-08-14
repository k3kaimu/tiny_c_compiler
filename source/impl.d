extern(C):

import core.stdc.stdio;
import core.stdc.stdlib;

int Main(FILE* fp, int argc, char** argv)
{
    if(argc != 2) {
        fprintf(stderr, "引数の個数が正しくありません\n");
        return 1;
    }

    fprintf(fp, "define i32 @main() {\n");
    fprintf(fp, "  ret i32 %d\n", atoi(argv[1]));
    fprintf(fp, "}\n");

    return 0;
}
