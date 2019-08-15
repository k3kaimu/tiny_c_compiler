extern(C):

import ast;
import utils;

import core.stdc.stdio;
import core.stdc.stdlib;


char[][] lvar_names;

void gen_llvm_ir_def_lvars(FILE* fp, Node* node)
{
    if(node is null)
        return;

    if(node.kind == NodeKind.LVAR) {
        // すでに定義されていないか探す
        foreach(char[] name; lvar_names)
            if(name == node.token.str)
                return;

        fprintf(fp, "  %%%.*s = alloca i32\n", node.token.str.length, node.token.str.ptr);
        lvar_names ~= node.token.str;
        return;
    }

    gen_llvm_ir_def_lvars(fp, node.lhs);
    gen_llvm_ir_def_lvars(fp, node.rhs);
}


void concat_ir(FILE* fp, FILE* tmp)
{
    int c;
    while(1) {
        c = fgetc(tmp);
        if(c == EOF) break;
        fputc(c, fp);
    }
    fclose(tmp);
}


FILE* gen_llvm_ir_block(Node* node, int* val_cnt)
{
    FILE* fp = tmpfile();
    gen_llvm_ir_stmt(fp, node, val_cnt);
    fflush(fp);
    rewind(fp);
    return fp;
}


void gen_llvm_ir_stmt(FILE* fp, Node* node, int* val_cnt)
{
    if(node.kind == NodeKind.IF) {
        int cond_id = gen_llvm_ir_expr(fp, node.cond, val_cnt);
        ++*val_cnt;
        fprintf(fp, "  %%%d = icmp ne i32 %%%d, 0\n", *val_cnt, cond_id);
        cond_id = *val_cnt;

        ++*val_cnt;
        int then_id = *val_cnt;
        FILE* then_ir = gen_llvm_ir_block(node.thenblock, val_cnt);

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
        FILE* then_ir = gen_llvm_ir_block(node.thenblock, val_cnt);

        ++*val_cnt;
        int else_id = *val_cnt;
        FILE* else_ir = gen_llvm_ir_block(node.elseblock, val_cnt);

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
