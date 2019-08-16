extern(C):

import ast;
import utils;
import typesys;

import core.stdc.stdio;
import core.stdc.stdlib;


void gen_llvm_ir_def_func(FILE* fp, Node* node)
{
    fprintf(fp, "define ");
    gen_llvm_ir_type(fp, node.ret_type);
    fprintf(fp, " @%.*s(", node.token.str.length, node.token.str.ptr);

    foreach(i, e; node.func_def_args) {
        // fprintf(fp, "i32");
        gen_llvm_ir_type(fp, e.type);
        if(i != node.func_def_args.length - 1)
            fprintf(fp, ", ");
    }
    fprintf(fp, ") {\n");
    fprintf(fp, "entry:\n");

    char[][] lvar_defined;

    foreach(i, e; node.func_def_args) {
        gen_llvm_ir_alloca(fp, e);
        gen_llvm_ir_store(fp, e, cast(int)i);
        lvar_defined ~= e.token.str;
    }

    foreach(e; node.func_def_body)
        gen_llvm_ir_def_lvars(fp, e, lvar_defined);

    int loop_cnt = 0;
    int var_cnt = cast(int)node.func_def_args.length;
    var_cnt -= 1;

    foreach(e; node.func_def_body)
        gen_llvm_ir_stmt(fp, e, &var_cnt, &loop_cnt);

    fprintf(fp, "  ret i32 -1\n");

    fprintf(fp, "}\n");
}

void gen_llvm_ir_def_lvars(FILE* fp, Node* node, ref char[][] lvar_defined)
{
    if(node is null)
        return;

    if(node.kind == NodeKind.LVAR_DEF) {
        // すでに定義されていないか探す
        foreach(char[] name; lvar_defined)
            if(name == node.def_var.token.str)
                return;

        gen_llvm_ir_alloca(fp, node.def_var);
        lvar_defined ~= node.def_var.token.str;
        return;
    }

    gen_llvm_ir_def_lvars(fp, node.lhs, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.rhs, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.cond, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.thenblock, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.elseblock, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.init_stmt, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.update_expr, lvar_defined);
    foreach(s; node.stmts)
        gen_llvm_ir_def_lvars(fp, s, lvar_defined);
}


void concat_ir(FILE* fp, FILE* tmp)
{
    rewind(tmp);
    int c;
    while(1) {
        c = fgetc(tmp);
        if(c == EOF) break;
        fputc(c, fp);
    }
    fclose(tmp);
}


FILE* gen_llvm_ir_stmt_block(Node* node, int* val_cnt, int* loop_cnt)
{
    FILE* fp = tmpfile();
    gen_llvm_ir_stmt(fp, node, val_cnt, loop_cnt);
    fflush(fp);
    return fp;
}


FILE* gen_llvm_ir_expr_block(Node* node, int* val_cnt)
{
    FILE* fp = tmpfile();
    gen_llvm_ir_expr(fp, node, val_cnt);
    fflush(fp);
    return fp;
}


void gen_llvm_ir_stmt(FILE* fp, Node* node, int* val_cnt, int* loop_cnt)
{
    if(node.kind == NodeKind.IF) {
        int cond_id = gen_llvm_ir_expr(fp, node.cond, val_cnt);
        ++*val_cnt;
        fprintf(fp, "  %%%d = icmp ne i32 %%%d, 0\n", *val_cnt, cond_id);
        cond_id = *val_cnt;

        ++*val_cnt;
        int then_id = *val_cnt;
        FILE* then_ir = gen_llvm_ir_stmt_block(node.thenblock, val_cnt, loop_cnt);

        ++*val_cnt;
        int next_id = *val_cnt;
        fprintf(fp, "  br i1 %%%d, label %%%d, label %%%d\n\n", cond_id, then_id, next_id);

        fprintf(fp, "; <label>:%%%d:\n", then_id);
        concat_ir(fp, then_ir);
        fprintf(fp, "  br label %%%d\n\n", next_id);

        fprintf(fp, "; <label>:%%%d:\n", next_id);
        return;
    } else if(node.kind == NodeKind.IFELSE) {
        int cond_id = gen_llvm_ir_expr(fp, node.cond, val_cnt);
        ++*val_cnt;
        fprintf(fp, "  %%%d = icmp ne i32 %%%d, 0\n", *val_cnt, cond_id);
        cond_id = *val_cnt;

        ++*val_cnt;
        int then_id = *val_cnt;
        FILE* then_ir = gen_llvm_ir_stmt_block(node.thenblock, val_cnt, loop_cnt);

        ++*val_cnt;
        int else_id = *val_cnt;
        FILE* else_ir = gen_llvm_ir_stmt_block(node.elseblock, val_cnt, loop_cnt);

        ++*val_cnt;
        int next_id = *val_cnt;
        fprintf(fp, "  br i1 %%%d, label %%%d, label %%%d\n\n", cond_id, then_id, else_id);

        fprintf(fp, "; <label>:%%%d:\n", then_id);
        concat_ir(fp, then_ir);
        fprintf(fp, "  br label %%%d\n\n", next_id);

        fprintf(fp, "; <label>:%%%d:\n", else_id);
        concat_ir(fp, else_ir);
        fprintf(fp, "  br label %%%d\n\n", next_id);

        fprintf(fp, "; <label>:%%%d:\n", next_id);
        return;
    } else if (node.kind == NodeKind.RETURN) {
        int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
        fprintf(fp, "  ret i32 %%%d\n\n", *val_cnt);
        ++*val_cnt;     // ret命令はBasic Blockを作るので，そのラベルを回避する
        return;
    } else if(node.kind == NodeKind.EXPR_STMT) {
        gen_llvm_ir_expr(fp, node.lhs, val_cnt);
        return;
    } else if(node.kind == NodeKind.BLOCK) {
        foreach(stmt; node.stmts)
            gen_llvm_ir_stmt(fp, stmt, val_cnt, loop_cnt);
        return;
    } else if(node.kind == NodeKind.FOR) {
        int this_loop_id = ++*loop_cnt;
        if(node.init_stmt !is null) gen_llvm_ir_stmt(fp, node.init_stmt, val_cnt, loop_cnt);

        int cond_block_id = ++*val_cnt;
        FILE* cond_ir = gen_llvm_ir_expr_block(node.cond, val_cnt);
        int cond_val_id = *val_cnt;
        int cond_val_bool_id = ++*val_cnt;

        int then_block_id = ++*val_cnt;
        FILE* then_ir = gen_llvm_ir_stmt_block(node.thenblock, val_cnt, loop_cnt);
        if(node.update_expr !is null) gen_llvm_ir_expr(then_ir, node.update_expr, val_cnt);
        fflush(then_ir);

        // int next_block_id = ++*val_cnt;

        fprintf(fp, "  br label %%%d\n\n", cond_block_id);
        fprintf(fp, "; <label>:%%%d:\n", cond_block_id);
        concat_ir(fp, cond_ir);
        fprintf(fp, "  %%%d = icmp ne i32 %%%d, 0\n", cond_val_bool_id, cond_val_id);
        // fprintf(fp, "  br i1 %%%d, label %%%d, label %%%d\n\n", cond_val_bool_id, then_block_id, next_block_id);
        fprintf(fp, "  br i1 %%%d, label %%%d, label %%L%d.end\n\n", cond_val_bool_id, then_block_id, this_loop_id);
        fprintf(fp, "; <label>:%%%d:\n", then_block_id);
        concat_ir(fp, then_ir);
        fprintf(fp, "  br label %%%d\n\n", cond_block_id);
        // fprintf(fp, "; <label>:%%%d:\n", next_block_id);
        fprintf(fp, "L%d.end:\n", this_loop_id);
        return;
    } else if(node.kind == NodeKind.BREAK) {
        fprintf(fp, "  br label %%L%d.end\n\n", *loop_cnt);
        ++*val_cnt;
        fprintf(fp, "; <label>:%%%d:\n", *val_cnt);
        return;
    } else if(node.kind == NodeKind.LVAR_DEF) {
        if(node.lhs !is null) {
            int init_val_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            gen_llvm_ir_store(fp, node.def_var, init_val_id);
        }
        return;
    } else {
        error("サポートしていない文です");
        return;
    }
}


int gen_llvm_ir_expr(FILE* fp, Node* node, int* val_cnt)
{
    if(node.kind == NodeKind.NUM) {
        ++*val_cnt;
        fprintf(fp, "  %%%d = add i32 0, %d\n", *val_cnt, node.val);
        return *val_cnt;
    }

    switch(node.kind) {
        case NodeKind.ADD:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = add i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            break;
        case NodeKind.SUB:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = sub i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            break;
        case NodeKind.MUL:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = mul i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            break;
        case NodeKind.DIV:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = sdiv i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            break;
        case NodeKind.EQ:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = icmp eq i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.NE:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = icmp ne i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.LT:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = icmp slt i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.LE:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = icmp sle i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.GT:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = icmp sgt i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.GE:
            int lhs_id = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = icmp sge i32 %%%d, %%%d\n", *val_cnt, lhs_id, rhs_id);
            goto Lzext;
        case NodeKind.LVAR:
            ++*val_cnt;
            fprintf(fp, "  %%%d = load i32, i32* %%%.*s\n", *val_cnt, node.token.str.length, node.token.str.ptr);
            break;
        case NodeKind.FUNC_CALL:
            int[] arg_ids;
            foreach(arg; node.func_call_args) {
                arg_ids ~= gen_llvm_ir_expr(fp, arg, val_cnt);
            }

            ++*val_cnt;
            fprintf(fp, "  %%%d = call i32 @%.*s(", *val_cnt, node.token.str.length, node.token.str.ptr);
            foreach(i, id; arg_ids) {
                fprintf(fp, "i32 %%%d", id);
                if(i != arg_ids.length -1)
                    fprintf(fp, ", ");
            }
            fprintf(fp, ")\n");

            break;
        case NodeKind.ASSIGN:
            char[] lhs_name = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            fprintf(fp, "  store i32 %%%d, i32* %%%.*s\n", rhs_id, lhs_name.length, lhs_name.ptr);
            ++*val_cnt;
            fprintf(fp, "  %%%d = load i32, i32* %%%.*s\n", *val_cnt, lhs_name.length, lhs_name.ptr);
            break;
        default:
            fprintf(stderr, "サポートしていないノードの種類です\n");
            exit(1);
            break;

        Lzext:
            fprintf(fp, "  %%%d = zext i1 %%%d to i32\n", *val_cnt + 1, *val_cnt);
            ++*val_cnt;
            break;
    }

    return *val_cnt;
}


char[] gen_llvm_ir_expr_lval(FILE* fp, Node* node, int* val_cnt)
{
    if(node.kind != NodeKind.LVAR && node.kind != NodeKind.ASSIGN)
        error("代入の左辺値が変数ではありません");

    switch(node.kind) {
        case NodeKind.LVAR:
            return node.token.str;
        
        case NodeKind.ASSIGN:
            char[] lhs_name = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            int rhs_id = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            fprintf(fp, "  store i32 %%%d, i32* %%%.*s\n", rhs_id, lhs_name.length, lhs_name.ptr);
            return lhs_name;

        default:
            fprintf(stderr, "サポートしていないノードの種類です\n");
            exit(1);
            break;
    }

    return null;
}


void gen_llvm_ir_type(FILE* fp, Type* type)
{
    if(type.kind == TypeKind.POINTER) {
        gen_llvm_ir_type(fp, type.nested);
        fprintf(fp, "*");
        return;
    } else {
        if(type.str == "int") {
            fprintf(fp, "i32");
            return;
        } else
            error("'%.*s': 不明な型です", type.str.length, type.str.ptr);
    }
}


void gen_llvm_ir_alloca(FILE* fp, Variable v)
{
    fprintf(fp, "  %%%.*s = alloca ", v.token.str.length, v.token.str.ptr);
    gen_llvm_ir_type(fp, v.type);
    fprintf(fp, "\n");
}


void gen_llvm_ir_store(FILE* fp, Variable v, int reg_id)
{
    fprintf(fp, "  store ");
    gen_llvm_ir_type(fp, v.type);
    fprintf(fp, " %%%d, ", reg_id);
    gen_llvm_ir_type(fp, v.type);
    fprintf(fp, "* %%%.*s\n", v.token.str.length, v.token.str.ptr);
}
