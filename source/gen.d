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
        RegType nested = make_llvm_ir_reg_type(type.nested);
        if(nested.str == "void")
            return ref_reg_type(RegType("i8"));
        else
            return ref_reg_type(nested);
    } else {
        if(type.str == "void")
            ret.str = "void";
        else if(type.str == "char" || type.str == "bool" || type.str == "byte")
            ret.str = "i8";
        else if(type.str == "short")
            ret.str = "i16";
        else if(type.str == "int")
            ret.str = "i32";
        else if(type.str == "long")
            ret.str = "i64";
        else
            error("'%.*s': 不明な型です", type.str.length, type.str.ptr);
    }

    return ret;
}


int sizeof_reg_type(RegType type)
{
    if(type.str.length && type.str[$-1] == '*')
        return 8;

    if(type.str == "i8")    return 1;
    if(type.str == "i16")   return 2;
    if(type.str == "i32")   return 4;
    if(type.str == "i64")   return 8;

    assert(0, "Unknown type: " ~ type.str);
    return -1;
}


RegType deref_reg_type(RegType ty)
{
    assert(ty.str[$-1] == '*');

    RegType ret = ty;
    ret.str = ret.str[0 .. $-1];
    return ret;
}


RegType ref_reg_type(RegType ty)
{
    RegType ret = ty;
    ret.str = ret.str ~ '*';
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


bool is_integer(Reg reg)
{
    string s = reg.type.str;

    return (s == "i1" || s == "i8" || s == "i16" || s == "i32" || s == "i64") ;
}


void gen_llvm_ir_reg_with_type(FILE* fp, Reg reg)
{
    if(reg.str) {
        fprintf(fp, "%.*s %%%.*s",
            reg.type.str.length, reg.type.str.ptr,
            reg.str.length, reg.str.ptr,
        );
    } else {
        fprintf(fp, "%.*s %%%d",
            reg.type.str.length, reg.type.str.ptr,
            reg.id
        );
    }
}


void gen_llvm_ir_reg(FILE* fp, Reg reg)
{
    if(reg.str) {
        fprintf(fp, "%%%.*s", reg.str.length, reg.str.ptr);
    } else {
        fprintf(fp, "%%%d", reg.id);
    }
}


Reg make_reg_id(RegType type, int id)
{
    Reg reg;
    reg.id = id;
    reg.str = null;
    reg.type = type;
    return reg;
}


Reg make_reg_str(RegType type, const(char)[] str)
{
    Reg reg;
    reg.id = -1;
    reg.str = str;
    reg.type = type;
    return reg;
}


Reg make_reg_from_Variable(Variable v)
{
    RegType ty = make_llvm_ir_reg_type(v.type);
    return make_reg_str(ref_reg_type(ty), v.token.str);
}


void gen_llvm_ir_decl_func(FILE* fp, Node* node)
{
    {
        RegType ret_type = make_llvm_ir_reg_type(node.ret_type);
        fprintf(fp, "declare %.*s @%.*s(",
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
    fprintf(fp, ")\n\n");
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
        Reg reg = gen_llvm_ir_alloca(fp, e.type, e.token.str);
        gen_llvm_ir_store(fp, make_reg_id(make_llvm_ir_reg_type(e.type), cast(int)i), reg);
        lvar_defined ~= e.token.str;
    }

    foreach(e; node.func_def_body)
        gen_llvm_ir_def_lvars(fp, e, lvar_defined);

    gen_llvm_ir_def_lvar(fp, node.ret_type, "__ret_var", lvar_defined);

    int block_cnt = 0;
    int loop_cnt = 0;
    int var_cnt = cast(int)node.func_def_args.length;
    var_cnt -= 1;

    RegType ret_type = make_llvm_ir_reg_type(node.ret_type);

    foreach(e; node.func_def_body)
        gen_llvm_ir_stmt(fp, e, &var_cnt, &loop_cnt, &block_cnt, ret_type);

    fprintf(fp, "  br label %%LRET\n\n");
    fprintf(fp, "LRET:\n");
    fprintf(fp, "  %%__ret_val = load %.*s, %.*s* %%__ret_var\n",
        ret_type.str.length, ret_type.str.ptr,
        ret_type.str.length, ret_type.str.ptr,
    );
    fprintf(fp, "  ret %.*s %%__ret_val\n",
        ret_type.str.length, ret_type.str.ptr
    );

    fprintf(fp, "}\n\n");
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


void gen_llvm_ir_stmt(FILE* fp, Node* node, int* val_cnt, int* loop_cnt, int* block_cnt, RegType ret_type)
{
    if(node.kind == NodeKind.IF || node.kind == NodeKind.IFELSE) {
        int this_block_id = ++*block_cnt;

        Reg cond_reg = gen_llvm_ir_expr(fp, node.cond, val_cnt);
        Reg cond_i8_reg = gen_llvm_ir_icmp_ne_0(fp, cond_reg, val_cnt);

        if(node.kind == NodeKind.IF) {  // if
            fprintf(fp, "  br i1 %%%d, label %%BIF%d.then, label %%BIF%d.next\n\n", cond_i8_reg.id, this_block_id, this_block_id);
        } else {                        // if-else
            fprintf(fp, "  br i1 %%%d, label %%BIF%d.then, label %%BIF%d.else\n\n", cond_i8_reg.id, this_block_id, this_block_id);
        }

        fprintf(fp, "BIF%d.then:\n", this_block_id);
        gen_llvm_ir_stmt(fp, node.thenblock, val_cnt, loop_cnt, block_cnt, ret_type);
        fprintf(fp, "  br label %%BIF%d.next\n\n", this_block_id);

        if(node.kind == NodeKind.IFELSE) {
            fprintf(fp, "BIF%d.else:\n", this_block_id);
            gen_llvm_ir_stmt(fp, node.elseblock, val_cnt, loop_cnt, block_cnt, ret_type);
            fprintf(fp, "  br label %%BIF%d.next\n\n", this_block_id);
        }

        fprintf(fp, "BIF%d.next:\n", this_block_id);
        gen_llvm_ir_dummy_op(fp, val_cnt);

        return;
    } else if (node.kind == NodeKind.RETURN) {
        Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
        gen_llvm_ir_store(fp, lhs_reg, make_reg_str(ref_reg_type(ret_type), "__ret_var"));
        fprintf(fp, "  br label %%LRET\n\n");
        ++*val_cnt;     // ret命令はBasic Blockを作るので，そのラベルを回避する
        fprintf(fp, "; <label>:%%%d:\n", *val_cnt);
        return;
    } else if(node.kind == NodeKind.EXPR_STMT) {
        gen_llvm_ir_expr(fp, node.lhs, val_cnt);
        return;
    } else if(node.kind == NodeKind.BLOCK) {
        foreach(stmt; node.stmts)
            gen_llvm_ir_stmt(fp, stmt, val_cnt, loop_cnt, block_cnt, ret_type);
        return;
    } else if(node.kind == NodeKind.FOR || node.kind == NodeKind.FOREACH) {
        int this_loop_id = ++*loop_cnt;

        Reg foreach_end_val_reg;        // foreachでend_expr()の評価結果のレジスタのid

        if(node.kind == NodeKind.FOR) { // for
            if(node.init_stmt !is null)
                gen_llvm_ir_stmt(fp, node.init_stmt, val_cnt, loop_cnt, block_cnt, ret_type);
        } else {                        // foreach
            Reg start_val_reg = gen_llvm_ir_expr(fp, node.start_expr, val_cnt);
            foreach_end_val_reg = gen_llvm_ir_expr(fp, node.end_expr, val_cnt);
            gen_llvm_ir_store(fp, start_val_reg, make_reg_from_Variable(node.def_loop_var.def_var));
        }

        fprintf(fp, "  br label %%LFOR%d.cond\n\n", this_loop_id);
        fprintf(fp, "LFOR%d.cond:\n", this_loop_id);

        Reg cond_val_i1_reg;
        if(node.kind == NodeKind.FOR) { // for
            Reg cond_val_reg = gen_llvm_ir_expr(fp, node.cond, val_cnt);
            cond_val_i1_reg = gen_llvm_ir_icmp_ne_0(fp, cond_val_reg, val_cnt);
        } else {                        // foreach
            Reg value_of_loop_var_reg = gen_llvm_ir_load(fp, make_reg_from_Variable(node.def_loop_var.def_var), val_cnt);
            cond_val_i1_reg = gen_llvm_ir_icmp(fp, NodeKind.LT, value_of_loop_var_reg, foreach_end_val_reg, val_cnt);
        }

        fprintf(fp, "  br i1 %%%d, label %%LFOR%d.then, label %%LFOR%d.end\n\n", cond_val_i1_reg.id, this_loop_id, this_loop_id);
        fprintf(fp, "LFOR%d.then:\n", this_loop_id);
        gen_llvm_ir_stmt(fp, node.thenblock, val_cnt, loop_cnt, block_cnt, ret_type);

        if(node.kind == NodeKind.FOR) { // for
            if(node.update_expr !is null)
                gen_llvm_ir_expr(fp, node.update_expr, val_cnt);
        } else {                        // foreach
            Reg value_of_loop_var_reg = gen_llvm_ir_load(fp, make_reg_from_Variable(node.def_loop_var.def_var), val_cnt);
            Reg next_val = gen_llvm_ir_binop_const(fp, "add", value_of_loop_var_reg, 1, val_cnt);
            gen_llvm_ir_store(fp, next_val, make_reg_from_Variable(node.def_loop_var.def_var));
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
            gen_llvm_ir_store(fp, init_val_reg, make_reg_from_Variable(node.def_var));
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
            RegType ty = make_llvm_ir_reg_type(node.type);
            fprintf(fp, "  %%%d = add %.*s 0, %d\n",
                ++*val_cnt,
                ty.str.length, ty.str.ptr,
                node.val);

            return make_reg_id(ty, *val_cnt);

        case NodeKind.ADD:
        case NodeKind.SUB:
        case NodeKind.MUL:
        case NodeKind.DIV:
        case NodeKind.REM:
            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            if(is_integer(lhs_reg) && is_integer(rhs_reg)) {
            assert(lhs_reg.type.str == rhs_reg.type.str);

            fprintf(fp, "  %%%d = ", ++*val_cnt);
            switch(node.kind) {
                case NodeKind.ADD: fprintf(fp, "add nsw "); break;
                case NodeKind.SUB: fprintf(fp, "sub "); break;
                case NodeKind.MUL: fprintf(fp, "mul nsw "); break;
                case NodeKind.DIV: fprintf(fp, "sdiv "); break;
                case NodeKind.REM: fprintf(fp, "srem "); break;
                default: assert(0);
            }

            gen_llvm_ir_reg_with_type(fp, lhs_reg);

            if(rhs_reg.str is null)
                fprintf(fp, ", %%%d\n", rhs_reg.id);
            else
                fprintf(fp, ", %%%.*s\n", rhs_reg.str.length, rhs_reg.str.ptr);

            return make_reg_id(lhs_reg.type, *val_cnt);
            } else if(is_pointer(lhs_reg) && is_integer(rhs_reg)) {
                if(node.kind == NodeKind.SUB)
                    rhs_reg = gen_llvm_ir_binop_const(fp, "mul", rhs_reg, -1, val_cnt);
                return gen_llvm_ir_getelementptr_inbounds(fp, lhs_reg, rhs_reg, val_cnt);
            } else if(is_integer(lhs_reg) && is_pointer(rhs_reg)) {
                assert(node.kind != NodeKind.SUB);

                return gen_llvm_ir_getelementptr_inbounds(fp, rhs_reg, lhs_reg, val_cnt);
            } else if(is_pointer(lhs_reg) && is_pointer(rhs_reg)) {
                assert(node.kind != NodeKind.ADD);
                assert(lhs_reg.type.str == rhs_reg.type.str);

                return gen_llvm_ir_distance_of_pointers(fp, lhs_reg, rhs_reg, val_cnt);
            } else {
                assert(0);
            }

        case NodeKind.EQ:
        case NodeKind.NE:
        case NodeKind.LT:
        case NodeKind.LE:
        case NodeKind.GT:
        case NodeKind.GE:
            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            Reg icmp_reg = gen_llvm_ir_icmp(fp, node.kind, lhs_reg, rhs_reg, val_cnt);
            RegType ty = make_llvm_ir_reg_type(node.type);
            return gen_llvm_ir_integer_cast(fp, ty, icmp_reg, val_cnt);

        case NodeKind.NOT:
            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            assert(lhs_reg.type.str == "i8");
            return gen_llvm_ir_binop_const(fp, "xor", lhs_reg, 1, val_cnt);

        case NodeKind.LVAR:
            RegType ty = make_llvm_ir_reg_type(node.type);
            gen_llvm_ir_load(fp, make_reg_str(ref_reg_type(ty), node.token.str), val_cnt);
            return make_reg_id(ty, *val_cnt);

        case NodeKind.FUNC_CALL:
            Reg[] arg_regs;
            foreach(arg; node.func_call_args) {
                arg_regs ~= gen_llvm_ir_expr(fp, arg, val_cnt);
            }

            RegType ret_reg_type = make_llvm_ir_reg_type(node.type);

            if(ret_reg_type.str != "void") {
                fprintf(fp, "  %%%d = ", ++*val_cnt);
            }

            fprintf(fp, "call %.*s @%.*s(",
                ret_reg_type.str.length, ret_reg_type.str.ptr,
                node.token.str.length, node.token.str.ptr,
            );
            foreach(i, e; arg_regs) {
                gen_llvm_ir_reg_with_type(fp, e);
                if(i != arg_regs.length -1)
                    fprintf(fp, ", ");
            }
            fprintf(fp, ")\n");

            if(ret_reg_type.str != "void")
            return make_reg_id(ret_reg_type, *val_cnt);
            else
                return make_reg_id(ret_reg_type, -1);

        case NodeKind.ASSIGN:
            Reg lhs_reg = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            gen_llvm_ir_store(fp, rhs_reg, lhs_reg);
            gen_llvm_ir_load(fp, lhs_reg, val_cnt);
            return make_reg_id(deref_reg_type(lhs_reg.type), *val_cnt);

        case NodeKind.CAST:
            assert(is_integer_type(node.type) || is_pointer_type(node.type));

            Reg lhs_reg = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            RegType ty = make_llvm_ir_reg_type(node.type);

            if(is_integer_type(node.type)) {
                if(node.type.str == "bool") {
                    assert(is_integer_type(node.lhs.type) || is_pointer_type(node.lhs.type));
                    auto i1_reg = gen_llvm_ir_icmp_ne_0(fp, lhs_reg, val_cnt);
                    return gen_llvm_ir_integer_cast(fp, ty, i1_reg, val_cnt);
                } else {
                assert(is_integer_type(node.lhs.type));
                    return gen_llvm_ir_integer_cast(fp, ty, lhs_reg, val_cnt);
                }
            } else if(is_pointer_type(node.type)) {
                assert(is_pointer_type(node.lhs.type));
                return gen_llvm_ir_pointer_cast(fp, ty, lhs_reg, val_cnt);
            }
            assert(0);

        case NodeKind.DOT:
            assert(node.token.str == "sizeof");
            if(node.token.str == "sizeof") {
                RegType ty = make_llvm_ir_reg_type(node.type);
                fprintf(fp, "  %%%d = add %.*s 0, %d\n",
                    ++*val_cnt,
                    ty.str.length, ty.str.ptr,
                    node.val);

                return make_reg_id(ty, *val_cnt);
            }
            break;
        case NodeKind.PRE_INC:
        case NodeKind.PRE_DEC:
        case NodeKind.POST_INC:
        case NodeKind.POST_DEC:
            Reg lhs = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            Reg lhs_val = gen_llvm_ir_load(fp, lhs, val_cnt);

            Reg lhs_inc;
            if(node.kind == NodeKind.PRE_INC || node.kind == NodeKind.POST_INC)
                lhs_inc = gen_llvm_ir_binop_const(fp, "add", lhs_val, 1, val_cnt);
            else
                lhs_inc = gen_llvm_ir_binop_const(fp, "sub", lhs_val, 1, val_cnt);

            gen_llvm_ir_store(fp, lhs_inc, lhs);
            if(node.kind == NodeKind.PRE_INC || node.kind == NodeKind.PRE_DEC)
                return lhs_inc;
            else
                return lhs_val;

        case NodeKind.PTR_REF:
            Reg lhs = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            return lhs;

        case NodeKind.PTR_DEREF:
            Reg lhs = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            assert(is_pointer(lhs));
            Reg lhs_val = gen_llvm_ir_load(fp, lhs, val_cnt);
            return lhs_val;

        default:
            error("サポートしていないノードの種類です");
            break;
    }

    assert(0);
}


Reg gen_llvm_ir_expr_lval(FILE* fp, Node* node, int* val_cnt)
{
    switch(node.kind) {
        case NodeKind.PRE_INC:
        case NodeKind.PRE_DEC:
            Reg lhs = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            Reg lhs_val = gen_llvm_ir_load(fp, lhs, val_cnt);

            Reg lhs_inc;
            if(node.kind == NodeKind.PRE_INC || node.kind == NodeKind.POST_INC)
                lhs_inc = gen_llvm_ir_binop_const(fp, "add", lhs_val, 1, val_cnt);
            else
                lhs_inc = gen_llvm_ir_binop_const(fp, "sub", lhs_val, 1, val_cnt);

            gen_llvm_ir_store(fp, lhs_inc, lhs);
            return lhs;

        case NodeKind.PTR_DEREF:
            Reg lhs = gen_llvm_ir_expr(fp, node.lhs, val_cnt);
            assert(is_pointer(lhs));
            return lhs;

        case NodeKind.LVAR:
            RegType ty = make_llvm_ir_reg_type(node.type);
            return make_reg_str(ref_reg_type(ty), node.token.str);
        
        case NodeKind.ASSIGN:
            Reg lhs_reg = gen_llvm_ir_expr_lval(fp, node.lhs, val_cnt);
            Reg rhs_reg = gen_llvm_ir_expr(fp, node.rhs, val_cnt);
            assert(deref_reg_type(lhs_reg.type).str == rhs_reg.type.str);
            gen_llvm_ir_store(fp, rhs_reg, lhs_reg);
            return lhs_reg;

        default:
            error("左辺値が得られないノードの種類です");
            break;
    }

    return make_reg_str(RegType(null), null);
}


Reg gen_llvm_ir_alloca(FILE* fp, Type* ty, const(char)[] lvarname)
{
    Reg reg;
    reg.str = lvarname;
    reg.type = make_llvm_ir_reg_type(ty);

    fprintf(fp, "  %%%.*s = alloca %.*s, align %d\n",
        reg.str.length, reg.str.ptr,
        reg.type.str.length, reg.type.str.ptr,
        sizeof_type(ty)
        );

    reg.type = ref_reg_type(reg.type);
    return reg;
}


void gen_llvm_ir_store(FILE* fp, Reg src, Reg dst)
{
    if(!is_pointer(dst) || deref_reg_type(dst.type).str != src.type.str) {
        error("gen_llvm_ir_store: 型が一致しません． typeof(dst) = %.*s, typeof(src) = %.*s",
            dst.type.str.length, dst.type.str.ptr,
            src.type.str.length, src.type.str.ptr,
        );
    }

    fprintf(fp, "  store ");
    gen_llvm_ir_reg_with_type(fp, src);
    fprintf(fp, ", ");
    gen_llvm_ir_reg_with_type(fp, dst);
    fprintf(fp, ", align %d\n", sizeof_reg_type(src.type));
}


Reg gen_llvm_ir_load(FILE* fp, Reg src, int* val_cnt)
{
    ++*val_cnt;

    if(!is_pointer(src)) {
        error("gen_llvm_ir_load: srcがポインタ型ではありません． typeof(src) = %.*s",
            src.type.str.length, src.type.str.ptr,
        );
    }

    string deref_type = deref_reg_type(src.type).str;
    fprintf(fp, "  %%%d = load %.*s, ",
        *val_cnt,
        deref_type.length, deref_type.ptr,
    );
    gen_llvm_ir_reg_with_type(fp, src);
    fprintf(fp, ", align %d\n", sizeof_reg_type(src.type));

    Reg reg;
    reg.type.str = deref_type;
    reg.id = *val_cnt;
    return reg;
}


Reg gen_llvm_ir_icmp(FILE* fp, NodeKind op_kind, Reg lhs_reg, Reg rhs_reg, int* val_cnt)
{
    assert(lhs_reg.type.str == rhs_reg.type.str);

    int result_i1_id = ++*val_cnt;

    fprintf(fp, "  %%%d = icmp ", result_i1_id);

    switch(op_kind) {
        case NodeKind.EQ:
            fprintf(fp, "eq ");
            break;
        case NodeKind.NE:
            fprintf(fp, "ne ");
            break;
        case NodeKind.LT:
            fprintf(fp, "slt ");
            break;
        case NodeKind.LE:
            fprintf(fp, "sle ");
            break;
        case NodeKind.GT:
            fprintf(fp, "sgt ");
            break;
        case NodeKind.GE:
            fprintf(fp, "sge ");
            break;
        default:
            error("'op_kind = %d': 比較演算子ではありません", cast(int)op_kind);
            break;
    }

    gen_llvm_ir_reg_with_type(fp, lhs_reg);

    if(rhs_reg.str is null)
        fprintf(fp, ", %%%d\n", rhs_reg.id);
    else
        fprintf(fp, ", %%%.*s\n", rhs_reg.str.length, rhs_reg.str.ptr);

    return make_reg_id(RegType("i1"), result_i1_id);
}


Reg gen_llvm_ir_icmp_ne_0(FILE* fp, Reg lhs_reg, int* val_cnt)
{
    fprintf(fp, "  %%%d = icmp ne ", ++*val_cnt);
    gen_llvm_ir_reg_with_type(fp, lhs_reg);
    if(is_pointer(lhs_reg))
        fprintf(fp, ", null\n");
    else
    fprintf(fp, ", 0\n");
    return make_reg_id(RegType("i1"), *val_cnt);
}


void gen_llvm_ir_dummy_op(FILE* fp, int* val_cnt)
{
    fprintf(fp, "  %%%d = add i32 0, 0\n", ++*val_cnt);
}


Reg gen_llvm_ir_integer_cast(FILE* fp, RegType ty, Reg val, int* val_cnt)
{
    assert(ty.str[0] == 'i');

    if(ty.str == val.type.str)
        return val;

    if(val.type.str == "i1") {
        fprintf(fp, "  %%%d = zext ", ++*val_cnt);
        gen_llvm_ir_reg_with_type(fp, val);
        fprintf(fp, " to %.*s\n",
            ty.str.length, ty.str.ptr,
        );
        return make_reg_id(ty, *val_cnt);
    }

    if(sizeof_reg_type(ty) < sizeof_reg_type(val.type)) {
        fprintf(fp, "  %%%d = trunc ", ++*val_cnt);
        gen_llvm_ir_reg_with_type(fp, val);
        fprintf(fp, " to %.*s\n",
            ty.str.length, ty.str.ptr,
        );
    } else {
        fprintf(fp, "  %%%d = sext ", ++*val_cnt);
        gen_llvm_ir_reg_with_type(fp, val);
        fprintf(fp, " to %.*s\n",
            ty.str.length, ty.str.ptr,
        );
    }

    return make_reg_id(ty, *val_cnt);
}


Reg gen_llvm_ir_pointer_cast(FILE* fp, RegType ty, Reg val, int* val_cnt)
{
    fprintf(fp, "  %%%d = bitcast ", ++*val_cnt);
    gen_llvm_ir_reg_with_type(fp, val);
    fprintf(fp, " to %.*s\n",
        ty.str.length, ty.str.ptr,
    );

    return make_reg_id(ty, *val_cnt);
}


Reg gen_llvm_ir_binop_const(FILE* fp, string op, Reg val, long v, int* val_cnt)
{
    fprintf(fp, "  %%%d = %.*s ",
        ++*val_cnt,
        op.length, op.ptr,
    );
    gen_llvm_ir_reg_with_type(fp, val);
    fprintf(fp, ", %lld\n", v);

    return make_reg_id(val.type, *val_cnt);
}


Reg gen_llvm_ir_binop(FILE* fp, string op, Reg lhs, Reg rhs, int* val_cnt)
{
    assert(lhs.type.str == rhs.type.str);

    fprintf(fp, "  %%%d = %.*s ",
        ++*val_cnt,
        op.length, op.ptr,
    );
    gen_llvm_ir_reg_with_type(fp, lhs);
    fprintf(fp, ", ");
    gen_llvm_ir_reg(fp, rhs);
    fprintf(fp, "\n");

    return make_reg_id(lhs.type, *val_cnt);
}


Reg gen_llvm_ir_getelementptr_inbounds(FILE* fp, Reg ptr, Reg offset, int* val_cnt)
{
    RegType deref_type = deref_reg_type(ptr.type);

    fprintf(fp, "  %%%d = getelementptr inbounds %.*s, ",
        ++*val_cnt,
        deref_type.str.length, deref_type.str.ptr,
    );
    gen_llvm_ir_reg_with_type(fp, ptr);
    fprintf(fp, ", ");
    gen_llvm_ir_reg_with_type(fp, offset);
    fprintf(fp, "\n");

    return make_reg_id(ptr.type, *val_cnt);
}


Reg gen_llvm_ir_ptr_to_i64(FILE* fp, Reg ptr, int* val_cnt)
{
    assert(is_pointer(ptr));

    fprintf(fp, "  %%%d = ptrtoint ", ++*val_cnt);
    gen_llvm_ir_reg_with_type(fp, ptr);
    fprintf(fp, " to i64\n");

    return make_reg_id(RegType("i64"), *val_cnt);
}


Reg gen_llvm_ir_distance_of_pointers(FILE* fp, Reg lhs, Reg rhs, int* val_cnt)
{
    Reg lhs_i64 = gen_llvm_ir_ptr_to_i64(fp, lhs, val_cnt);
    Reg rhs_i64 = gen_llvm_ir_ptr_to_i64(fp, rhs, val_cnt);
    Reg diff = gen_llvm_ir_binop(fp, "sub", lhs_i64, rhs_i64, val_cnt);
    return gen_llvm_ir_binop_const(fp, "sdiv exact", diff, sizeof_reg_type(deref_reg_type(lhs.type)), val_cnt);
}
