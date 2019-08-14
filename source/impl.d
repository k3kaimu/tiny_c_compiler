extern(C):

import tokenizer;
import utils;

import core.stdc.stdio;


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
