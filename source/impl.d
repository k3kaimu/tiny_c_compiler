extern(C):

import tokenizer;
import utils;
import ast;
import gen;
import sema;

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
    Node*[] func_decl_defs = program();

    semantic_analysis(func_decl_defs);

    LLVM_IR_Env env;
    env.header_fp = tmpfile();
    env.fp = tmpfile();
    env.constval_cnt = 0;
    gen_llvm_ir_decl_def(&env, func_decl_defs);

    concat_ir(fp, env.header_fp);
    concat_ir(fp, env.fp);

    return 0;
}
