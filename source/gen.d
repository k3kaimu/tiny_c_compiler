extern(C):

import ast;
import utils;
import typesys;

import core.stdc.stdio;
import core.stdc.stdlib;


struct RegType
{
    string str;
}


RegType make_llvm_ir_reg_type(Type* type)
{
    RegType ret;

    if(type.kind == TypeKind.POINTER) {
        ret.str = make_llvm_ir_reg_type(type.nested).str ~ "*";
    } else {
        if(type.str == "int")
            ret.str = "i32";
        else
            error("'%.*s': 不明な型です", type.str.length, type.str.ptr);
    }

    return ret;
}


struct Reg
{
    int id;
    const(char)[] str;
    RegType type;
}


bool is_pointer(Reg reg)
{
    return reg.type.str[$-1] == '*';
}


Reg make_reg_id(int id)
{
    Reg reg;
    reg.id = id;
    reg.str = null;
    reg.type.str = "i32";
    return reg;
}


Reg make_reg_str(char[] str)
{
    Reg reg;
    reg.id = -1;
    reg.str = str;
    reg.type.str = "i32*";
    return reg;
}


void gen_llvm_ir_def_func(FILE* fp, Node* node)
{
    {
        RegType ret_type = make_llvm_ir_reg_type(node.ret_type);
        fprintf(fp, "define %.*s @%.*s(",
            ret_type.str.length, ret_type.str.ptr,
            node.token.str.length, node.token.str.ptr
        );
    }

    foreach(i, e; node.func_def_args) {
        RegType arg_type = make_llvm_ir_reg_type(e.type);
        fprintf(fp, "%.*s", arg_type.str.length, arg_type.str.ptr);
        if(i != node.func_def_args.length - 1)
            fprintf(fp, ", ");
    }
    fprintf(fp, ") {\n");
    fprintf(fp, "entry:\n");

    const(char[])[] lvar_defined;

    foreach(i, e; node.func_def_args) {
        gen_llvm_ir_alloca(fp, e.type, e.token.str);
        gen_llvm_ir_store(fp, e, cast(int)i);
        lvar_defined ~= e.token.str;
    }

    foreach(e; node.func_def_body)
        gen_llvm_ir_def_lvars(fp, e, lvar_defined);

    gen_llvm_ir_def_lvar(fp, node.ret_type, "__ret_var", lvar_defined);

    int block_cnt = 0;
    int loop_cnt = 0;
    int var_cnt = cast(int)node.func_def_args.length;
    var_cnt -= 1;

    foreach(e; node.func_def_body)
        gen_llvm_ir_stmt(fp, e, &var_cnt, &loop_cnt, &block_cnt);

    fprintf(fp, "  br label %%LRET\n\n");
    fprintf(fp, "LRET:\n");
    fprintf(fp, "  %%__ret_val = load i32, i32* %%__ret_var\n");
    fprintf(fp, "  ret i32 %%__ret_val\n", var_cnt);

    fprintf(fp, "}\n");
}


void gen_llvm_ir_def_lvar(FILE* fp, Type* ty, const(char)[] lvarname, ref const(char[])[] lvar_defined)
{
    // すでに定義されていないか探す
    foreach(const(char)[] name; lvar_defined)
        if(name == lvarname)
            return;

    gen_llvm_ir_alloca(fp, ty, lvarname);
    lvar_defined ~= lvarname;
    return;
}


void gen_llvm_ir_def_lvars(FILE* fp, Node* node, ref const(char[])[] lvar_defined)
{
    if(node is null)
        return;

    if(node.kind == NodeKind.LVAR_DEF) {
        gen_llvm_ir_def_lvar(fp, node.def_var.type, node.def_var.token.str, lvar_defined);
        return;
    }

    gen_llvm_ir_def_lvars(fp, node.lhs, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.rhs, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.cond, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.thenblock, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.elseblock, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.init_stmt, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.update_expr, lvar_defined);
    gen_llvm_ir_def_lvars(fp, node.def_loop_var, lvar_defined);
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


void gen_llvm_ir_stmt(FILE* fp, Node* node, int* val_cnt, int* loop_cnt, int* block_cnt)
{
    if(node.kind == NodeKind.IF || node.kind == NodeKind.IFELSE) {
        int this_block_id = ++*block_cnt;

        Reg cond_reg = gen_llvm_ir_expr(fp, node.cond, val_cnt);
        Reg cond_i8_reg = gen_llvm_ir_icmp_ne_0(fp, cond_reg.id, val_cnt);

        if(node.kind == NodeKind.IF) {  // if
            fprintf(fp, "  br i1 %%%d, label %%BIF%d.then, label %%BIF%d.next\n\n", cond_i8_reg.id, this_block_id, this_block_id);
        } else {                        // if-else
            fprintf(fp, "  br i1 %%%d, label %%BIF%d.then, label %%BIF%d.else\n\n", cond_i8_reg.id, this_block_id, this_block_id);
        }

        fprintf(fp, "BIF%d.then:\n", this_block_id);
        gen_llvm_ir_stmt(fp, node.thenblock, val_cnt, loop_cnt, block_cnt);
        fprintf(fp, "  br label %%BIF%d.next\n\n", this_block_id);

        if(node.kind == NodeKind.IFELSE) {
            fprintf(fp, "BIF%d.else:\n", this_block_id);
            gen_llvm_ir_stmt(fp, node.elseblock, val_cnt, loop_cnt, block_cnt);
            fprintf(fp, "  br label %%BIF%d.next\n\n", this_block_id);
        }

        fprintf(fp, "BIF%d.next:\n", this_block_id);
        gen_llvm_ir_dummy_op(fp, val_cnt);

        return;
    } else if (node.kind == NodeKind.RETURN) {
        Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
        fprintf(fp, "  store i32 %%%d, i32* %%__ret_var\n", lhs_reg.id);
        fprintf(fp, "  br label %%LRET\n\n");
        ++*val_cnt;     // ret命令はBasic Blockを作るので，そのラベルを回避する
        fprintf(fp, "; <label>:%%%d:\n", *val_cnt);
        return;
    } else if(node.kind == NodeKind.EXPR_STMT) {
        gen_llvm_ir_expr(fp, node.lhs, val_cnt);
        return;
    } else if(node.kind == NodeKind.BLOCK) {
        foreach(stmt; node.stmts)
            gen_llvm_ir_stmt(fp, stmt, val_cnt, loop_cnt, block_cnt);
        return;
    } else if(node.kind == NodeKind.FOR || node.kind == NodeKind.FOREACH) {
        int this_loop_id = ++*loop_cnt;

        Reg foreach_end_val_reg;        // foreachでend_expr()の評価結果のレジスタのid

        if(node.kind == NodeKind.FOR) { // for
            if(node.init_stmt !is null)
                gen_llvm_ir_stmt(fp, node.init_stmt, val_cnt, loop_cnt, block_cnt);
        } else {                        // foreach
            Reg start_val_reg = gen_llvm_ir_expr(fp, node.start_expr, val_cnt);
            foreach_end_val_reg = gen_llvm_ir_expr(fp, node.end_expr, val_cnt);
            gen_llvm_ir_store(fp, node.def_loop_var.def_var, start_val_reg.id);
        }

        fprintf(fp, "  br label %%LFOR%d.cond\n\n", this_loop_id);
        fprintf(fp, "LFOR%d.cond:\n", this_loop_id);

        Reg cond_val_i1_reg;
        if(node.kind == NodeKind.FOR) { // for
            Reg cond_val_reg = gen_llvm_ir_expr(fp, node.cond, val_cnt);
            cond_val_i1_reg = gen_llvm_ir_icmp_ne_0(fp, cond_val_reg.id, val_cnt);
        } else {                        // foreach
            int value_of_loop_var_id = ++*val_cnt;
            fprintf(fp, "  %%%d = load i32, i32* %%%.*s\n",
                value_of_loop_var_id,
                node.def_loop_var.def_var.token.str.length, node.def_loop_var.def_var.token.str.ptr,
            );
            cond_val_i1_reg = gen_llvm_ir_icmp(fp, NodeKind.LT, value_of_loop_var_id, foreach_end_val_reg.id, val_cnt);
        }

        fprintf(fp, "  br i1 %%%d, label %%LFOR%d.then, label %%LFOR%d.end\n\n", cond_val_i1_reg.id, this_loop_id, this_loop_id);
        fprintf(fp, "LFOR%d.then:\n", this_loop_id);
        gen_llvm_ir_stmt(fp, node.thenblock, val_cnt, loop_cnt, block_cnt);

        if(node.kind == NodeKind.FOR) { // for
            if(node.update_expr !is null)
                gen_llvm_ir_expr(fp, node.update_expr, val_cnt);
        } else {                        // foreach
            int value_of_loop_var_id = ++*val_cnt;
             fprintf(fp, "  %%%d = load i32, i32* %%%.*s\n",
                value_of_loop_var_id,
                node.def_loop_var.def_var.token.str.length, node.def_loop_var.def_var.token.str.ptr,
            );
            int next_value_id = ++*val_cnt;
            fprintf(fp, "  %%%d = add i32 %%%d, 1\n", next_value_id, value_of_loop_var_id);
            gen_llvm_ir_store(fp, node.def_loop_var.def_var, next_value_id);
        }

        fprintf(fp, "  br label %%LFOR%d.cond\n\n", this_loop_id);
        fprintf(fp, "LFOR%d.end:\n", this_loop_id);
        gen_llvm_ir_dummy_op(fp, val_cnt);
        return;
    } else if(node.kind == NodeKind.BREAK) {
        fprintf(fp, "  br label %%LFOR%d.end\n\n", *loop_cnt);
        ++*val_cnt;
        fprintf(fp, "; <label>:%%%d:\n", *val_cnt);
        return;
    } else if(node.kind == NodeKind.LVAR_DEF) {
        if(node.lhs !is null) {
            Reg init_val_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            gen_llvm_ir_store(fp, node.def_var, init_val_reg.id);
        }
        return;
    } else {
        error("サポートしていない文です");
        return;
    }
}


Reg gen_llvm_ir_expr(FILE* fp, Node* node, int* val_cnt)
{
    switch(node.kind) {
        case NodeKind.NUM:
            ++*val_cnt;
            fprintf(fp, "  %%%d = add i32 0, %d\n", *val_cnt, node.val);
            break;

        case NodeKind.ADD:
            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = add i32 %%%d, %%%d\n", *val_cnt, lhs_reg.id, rhs_reg.id);
            break;
        case NodeKind.SUB:
            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = sub i32 %%%d, %%%d\n", *val_cnt, lhs_reg.id, rhs_reg.id);
            break;
        case NodeKind.MUL:
            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = mul i32 %%%d, %%%d\n", *val_cnt, lhs_reg.id, rhs_reg.id);
            break;
        case NodeKind.DIV:
            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            ++*val_cnt;
            fprintf(fp, "  %%%d = sdiv i32 %%%d, %%%d\n", *val_cnt, lhs_reg.id, rhs_reg.id);
            break;
        case NodeKind.EQ:
        case NodeKind.NE:
        case NodeKind.LT:
        case NodeKind.LE:
        case NodeKind.GT:
        case NodeKind.GE:
            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            Reg icmp_reg = gen_llvm_ir_icmp(fp, node.kind, lhs_reg.id, rhs_reg.id, val_cnt);
            fprintf(fp, "  %%%d = zext i1 %%%d to i32\n", ++*val_cnt, icmp_reg.id);
            break;
        case NodeKind.LVAR:
            ++*val_cnt;
            fprintf(fp, "  %%%d = load i32, i32* %%%.*s\n", *val_cnt, node.token.str.length, node.token.str.ptr);
            break;
        case NodeKind.FUNC_CALL:
            int[] arg_ids;
            foreach(arg; node.func_call_args) {
                arg_ids ~= gen_llvm_ir_expr(fp, arg, val_cnt).id;
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
            Reg lhs_reg = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            fprintf(fp, "  store i32 %%%d, i32* %%%.*s\n", rhs_reg.id, lhs_reg.str.length, lhs_reg.str.ptr);
            ++*val_cnt;
            fprintf(fp, "  %%%d = load i32, i32* %%%.*s\n", *val_cnt, lhs_reg.str.length, lhs_reg.str.ptr);
            break;
        default:
            fprintf(stderr, "サポートしていないノードの種類です\n");
            exit(1);
            break;
    }

    return make_reg_id(*val_cnt);
}


Reg gen_llvm_ir_expr_lval(FILE* fp, Node* node, int* val_cnt)
{
    if(node.kind != NodeKind.LVAR && node.kind != NodeKind.ASSIGN)
        error("代入の左辺値が変数ではありません");

    switch(node.kind) {
        case NodeKind.LVAR:
            return make_reg_str(node.token.str);
        
        case NodeKind.ASSIGN:
            Reg lhs_reg = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            fprintf(fp, "  store i32 %%%d, i32* %%%.*s\n", rhs_reg.id, lhs_reg.str.length, lhs_reg.str.ptr);
            return lhs_reg;

        default:
            fprintf(stderr, "サポートしていないノードの種類です\n");
            exit(1);
            break;
    }

    return make_reg_str(null);
}


Reg gen_llvm_ir_alloca(FILE* fp, Type* ty, const(char)[] lvarname)
{
    Reg reg;
    reg.str = lvarname;
    reg.type = make_llvm_ir_reg_type(ty);

    fprintf(fp, "  %%%.*s = alloca %.*s\n",
        reg.str.length, reg.str.ptr,
        reg.type.str.length, reg.type.str.ptr,
        );

    reg.type.str = reg.type.str ~ "*";
    return reg;
}


void gen_llvm_ir_store(FILE* fp, Variable v, int reg_id)
{
    RegType ty = make_llvm_ir_reg_type(v.type);
    fprintf(fp, "  store %.*s %%%d, %.*s* %%%.*s\n",
        ty.str.length, ty.str.ptr,
        reg_id,
        ty.str.length, ty.str.ptr,
        v.token.str.length, v.token.str.ptr
    );
}


Reg gen_llvm_ir_icmp(FILE* fp, NodeKind op_kind, int lhs_id, int rhs_id, int* val_cnt)
{
    int result_i8_id = ++*val_cnt;

    switch(op_kind) {
        case NodeKind.EQ:
            fprintf(fp, "  %%%d = icmp eq i32 %%%d, %%%d\n", result_i8_id, lhs_id, rhs_id);
            break;
        case NodeKind.NE:
            fprintf(fp, "  %%%d = icmp ne i32 %%%d, %%%d\n", result_i8_id, lhs_id, rhs_id);
            break;
        case NodeKind.LT:
            fprintf(fp, "  %%%d = icmp slt i32 %%%d, %%%d\n", result_i8_id, lhs_id, rhs_id);
            break;
        case NodeKind.LE:
            fprintf(fp, "  %%%d = icmp sle i32 %%%d, %%%d\n", result_i8_id, lhs_id, rhs_id);
            break;
        case NodeKind.GT:
            fprintf(fp, "  %%%d = icmp sgt i32 %%%d, %%%d\n", result_i8_id, lhs_id, rhs_id);
            break;
        case NodeKind.GE:
            fprintf(fp, "  %%%d = icmp sge i32 %%%d, %%%d\n", result_i8_id, lhs_id, rhs_id);
            break;
        default:
            error("'op_kind = %d': 比較演算子ではありません", cast(int)op_kind);
            break;
    }

    return make_reg_id(result_i8_id);
}

Reg gen_llvm_ir_init_i32_reg(FILE* fp, int value, int* val_cnt)
{
    ++*val_cnt;
    fprintf(fp, "  %%%d = add i32 0, %d\n", *val_cnt, value);
    return make_reg_id(*val_cnt);
}


Reg gen_llvm_ir_icmp_ne_0(FILE* fp, int lhs_id, int* val_cnt)
{
    ++*val_cnt;
    fprintf(fp, "  %%%d = icmp ne i32 %%%d, 0\n", *val_cnt, lhs_id);
    return make_reg_id(*val_cnt);
}


void gen_llvm_ir_dummy_op(FILE* fp, int* val_cnt)
{
    fprintf(fp, "  %%%d = add i32 0, 0\n", ++*val_cnt);
}
