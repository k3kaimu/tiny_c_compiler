extern(C):

import tokenizer;
import utils;
import ast;
import gen;

import core.stdc.stdio;
import core.stdc.string;


int Main(FILE* fp, int argc, char** argv)
{
    if(argc != 2) {
        fprintf(stderr, "引数の個数が正しくありません\n");
        return 1;
    }

    user_input = argv[1];
    size_t input_len = strlen(argv[1]);
    token = tokenize(argv[1][0 .. input_len]);
    Node*[] codes = program();

    fprintf(fp, "define i32 @main() {\n");

    lvar_names = null;
    foreach(node; codes)
        gen_llvm_ir_def_lvars(fp, node);

    int val_cnt = 0;

    foreach(node; codes)
        gen_llvm_ir_stmt(fp, node, &val_cnt);

    fprintf(fp, "  ret i32 %%%d\n", val_cnt);
    fprintf(fp, "}\n");

    return 0;
}
