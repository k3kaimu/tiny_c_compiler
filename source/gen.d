extern(C):

import ast;
import utils;
import typesys;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.ctype;


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


struct LLVM_IR_Env
{
    FILE* header_fp;
    FILE* fp;
    int val_cnt;
    int loop_cnt;
    int block_cnt;
    int constval_cnt;
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


void gen_llvm_ir_decl_def(LLVM_IR_Env* env, Node*[] program)
{
    foreach(e; program) {
        if(e.kind == NodeKind.FUNC_DECL)
            gen_llvm_ir_decl_func(env, e);
        else
            gen_llvm_ir_def_func(env, e);

        fprintf(env.fp, "\n");
    }
}


void gen_llvm_ir_decl_func(LLVM_IR_Env* env, Node* node)
{
    {
        RegType ret_type = make_llvm_ir_reg_type(node.ret_type);
        fprintf(env.fp, "declare %.*s @%.*s(",
            ret_type.str.length, ret_type.str.ptr,
            node.token.str.length, node.token.str.ptr
        );
    }

    foreach(i, e; node.func_def_args) {
        RegType arg_type = make_llvm_ir_reg_type(e.type);
        fprintf(env.fp, "%.*s", arg_type.str.length, arg_type.str.ptr);
        if(i != node.func_def_args.length - 1)
            fprintf(env.fp, ", ");
    }
    fprintf(env.fp, ")\n\n");
}


void gen_llvm_ir_def_func(LLVM_IR_Env* env, Node* node)
{
    {
        RegType ret_type = make_llvm_ir_reg_type(node.ret_type);
        fprintf(env.fp, "define %.*s @%.*s(",
            ret_type.str.length, ret_type.str.ptr,
            node.token.str.length, node.token.str.ptr
        );
    }

    foreach(i, e; node.func_def_args) {
        RegType arg_type = make_llvm_ir_reg_type(e.type);
        fprintf(env.fp, "%.*s", arg_type.str.length, arg_type.str.ptr);
        if(i != node.func_def_args.length - 1)
            fprintf(env.fp, ", ");
    }
    fprintf(env.fp, ") {\n");
    fprintf(env.fp, "entry:\n");

    const(char[])[] lvar_defined;

    env.block_cnt = 0;
    env.loop_cnt = 0;
    env.val_cnt = cast(int)node.func_def_args.length - 1;

    foreach(i, e; node.func_def_args) {
        Reg reg = gen_llvm_ir_alloca(env, e.type, e.token.str);
        gen_llvm_ir_store(env, make_reg_id(make_llvm_ir_reg_type(e.type), cast(int)i), reg);
        lvar_defined ~= e.token.str;
    }

    foreach(e; node.func_def_body)
        gen_llvm_ir_def_lvars(env, e, lvar_defined);

    gen_llvm_ir_def_lvar(env, node.ret_type, "__ret_var", lvar_defined);

    RegType ret_type = make_llvm_ir_reg_type(node.ret_type);

    foreach(e; node.func_def_body)
        gen_llvm_ir_stmt(env, e);

    fprintf(env.fp, "  br label %%LRET\n\n");
    fprintf(env.fp, "LRET:\n");
    fprintf(env.fp, "  %%__ret_val = load %.*s, %.*s* %%__ret_var\n",
        ret_type.str.length, ret_type.str.ptr,
        ret_type.str.length, ret_type.str.ptr,
    );
    fprintf(env.fp, "  ret %.*s %%__ret_val\n",
        ret_type.str.length, ret_type.str.ptr
    );

    fprintf(env.fp, "}\n\n");
}


void gen_llvm_ir_def_lvar(LLVM_IR_Env* env, Type* ty, const(char)[] lvarname, ref const(char[])[] lvar_defined)
{
    // すでに定義されていないか探す
    foreach(const(char)[] name; lvar_defined)
        if(name == lvarname)
            return;

    gen_llvm_ir_alloca(env, ty, lvarname);
    lvar_defined ~= lvarname;
    return;
}


void gen_llvm_ir_def_lvars(LLVM_IR_Env* env, Node* node, ref const(char[])[] lvar_defined)
{
    if(node is null)
        return;

    if(node.kind == NodeKind.LVAR_DEF) {
        gen_llvm_ir_def_lvar(env, node.def_var.type, node.def_var.token.str, lvar_defined);
        return;
    }

    gen_llvm_ir_def_lvars(env, node.lhs, lvar_defined);
    gen_llvm_ir_def_lvars(env, node.rhs, lvar_defined);
    gen_llvm_ir_def_lvars(env, node.cond, lvar_defined);
    gen_llvm_ir_def_lvars(env, node.thenblock, lvar_defined);
    gen_llvm_ir_def_lvars(env, node.elseblock, lvar_defined);
    gen_llvm_ir_def_lvars(env, node.init_stmt, lvar_defined);
    gen_llvm_ir_def_lvars(env, node.update_expr, lvar_defined);
    gen_llvm_ir_def_lvars(env, node.def_loop_var, lvar_defined);
    foreach(s; node.stmts)
        gen_llvm_ir_def_lvars(env, s, lvar_defined);
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


void gen_llvm_ir_stmt(LLVM_IR_Env* env, Node* node)
{
    if(node.kind == NodeKind.IF || node.kind == NodeKind.IFELSE) {
        int this_block_id = ++env.block_cnt;

        Reg cond_reg = gen_llvm_ir_expr(env, node.cond);
        Reg cond_i8_reg = gen_llvm_ir_icmp_ne_0(env, cond_reg);

        if(node.kind == NodeKind.IF) {  // if
            fprintf(env.fp, "  br i1 %%%d, label %%BIF%d.then, label %%BIF%d.next\n\n", cond_i8_reg.id, this_block_id, this_block_id);
        } else {                        // if-else
            fprintf(env.fp, "  br i1 %%%d, label %%BIF%d.then, label %%BIF%d.else\n\n", cond_i8_reg.id, this_block_id, this_block_id);
        }

        fprintf(env.fp, "BIF%d.then:\n", this_block_id);
        gen_llvm_ir_stmt(env, node.thenblock);
        fprintf(env.fp, "  br label %%BIF%d.next\n\n", this_block_id);

        if(node.kind == NodeKind.IFELSE) {
            fprintf(env.fp, "BIF%d.else:\n", this_block_id);
            gen_llvm_ir_stmt(env, node.elseblock);
            fprintf(env.fp, "  br label %%BIF%d.next\n\n", this_block_id);
        }

        fprintf(env.fp, "BIF%d.next:\n", this_block_id);
        gen_llvm_ir_dummy_op(env);
        return;

    } else if (node.kind == NodeKind.RETURN) {
        Reg lhs_reg = gen_llvm_ir_expr(env, node.lhs);
        gen_llvm_ir_store(env, lhs_reg, make_reg_str(ref_reg_type(lhs_reg.type), "__ret_var"));
        fprintf(env.fp, "  br label %%LRET\n\n");
        ++env.val_cnt;     // ret命令はBasic Blockを作るので，そのラベルを回避する
        fprintf(env.fp, "; <label>:%%%d:\n", env.val_cnt);
        return;
    } else if(node.kind == NodeKind.EXPR_STMT) {
        gen_llvm_ir_expr(env, node.lhs);
        return;
    } else if(node.kind == NodeKind.BLOCK) {
        foreach(stmt; node.stmts)
            gen_llvm_ir_stmt(env, stmt);
        return;
    } else if(node.kind == NodeKind.FOR || node.kind == NodeKind.FOREACH) {
        int this_loop_id = ++env.loop_cnt;

        Reg foreach_end_val_reg;        // foreachでend_expr()の評価結果のレジスタのid

        if(node.kind == NodeKind.FOR) { // for
            if(node.init_stmt !is null)
                gen_llvm_ir_stmt(env, node.init_stmt);
        } else {                        // foreach
            Reg start_val_reg = gen_llvm_ir_expr(env, node.start_expr);
            foreach_end_val_reg = gen_llvm_ir_expr(env, node.end_expr);
            gen_llvm_ir_store(env, start_val_reg, make_reg_from_Variable(node.def_loop_var.def_var));
        }

        fprintf(env.fp, "  br label %%LFOR%d.cond\n\n", this_loop_id);
        fprintf(env.fp, "LFOR%d.cond:\n", this_loop_id);

        Reg cond_val_i1_reg;
        if(node.kind == NodeKind.FOR) { // for
            Reg cond_val_reg = gen_llvm_ir_expr(env, node.cond);
            cond_val_i1_reg = gen_llvm_ir_icmp_ne_0(env, cond_val_reg);
        } else {                        // foreach
            Reg value_of_loop_var_reg = gen_llvm_ir_load(env, make_reg_from_Variable(node.def_loop_var.def_var));
            cond_val_i1_reg = gen_llvm_ir_icmp(env, NodeKind.LT, value_of_loop_var_reg, foreach_end_val_reg);
        }

        fprintf(env.fp, "  br i1 %%%d, label %%LFOR%d.then, label %%LFOR%d.end\n\n", cond_val_i1_reg.id, this_loop_id, this_loop_id);
        fprintf(env.fp, "LFOR%d.then:\n", this_loop_id);
        gen_llvm_ir_stmt(env, node.thenblock);

        if(node.kind == NodeKind.FOR) { // for
            if(node.update_expr !is null)
                gen_llvm_ir_expr(env, node.update_expr);
        } else {                        // foreach
            Reg value_of_loop_var_reg = gen_llvm_ir_load(env, make_reg_from_Variable(node.def_loop_var.def_var));
            Reg next_val = gen_llvm_ir_binop_const(env, "add", value_of_loop_var_reg, 1);
            gen_llvm_ir_store(env, next_val, make_reg_from_Variable(node.def_loop_var.def_var));
        }

        fprintf(env.fp, "  br label %%LFOR%d.cond\n\n", this_loop_id);
        fprintf(env.fp, "LFOR%d.end:\n", this_loop_id);
        gen_llvm_ir_dummy_op(env);
        return;
    } else if(node.kind == NodeKind.BREAK) {
        fprintf(env.fp, "  br label %%LFOR%d.end\n\n", env.loop_cnt);
        ++env.val_cnt;
        fprintf(env.fp, "; <label>:%%%d:\n", env.val_cnt);
        return;
    } else if(node.kind == NodeKind.LVAR_DEF) {
        if(node.lhs !is null) {
            Reg init_val_reg = gen_llvm_ir_expr(env, node.lhs);
            gen_llvm_ir_store(env, init_val_reg, make_reg_from_Variable(node.def_var));
        }
        return;
    } else {
        error("サポートしていない文です");
        return;
    }
}


Reg gen_llvm_ir_expr(LLVM_IR_Env* env, Node* node)
{
    switch(node.kind) {
        case NodeKind.NUM:
            RegType ty = make_llvm_ir_reg_type(node.type);
            fprintf(env.fp, "  %%%d = add %.*s 0, %d\n",
                ++env.val_cnt,
                ty.str.length, ty.str.ptr,
                node.val);

            return make_reg_id(ty, env.val_cnt);

        case NodeKind.STR_LIT:
            RegType ty = make_llvm_ir_reg_type(node.type);
            long len = node.str_lit_data.length;

            fprintf(env.header_fp, "@.constval.%d = private unnamed_addr constant [%lld x i8] c\"",
                ++env.constval_cnt, len
            );
            foreach(ubyte c; node.str_lit_data) {
                if(isprint(c)) {
                    fputc(c, env.header_fp);
                } else {
                    fprintf(env.header_fp, "\\%02X", c);
                }
            }
            fprintf(env.header_fp, "\", align 1\n\n");
            fprintf(env.fp, "  %%%d  = getelementptr inbounds [%lld x i8], [%lld x i8]* @.constval.%d, i32 0, i32 0\n",
                ++env.val_cnt, len, len, env.constval_cnt
            );

            return make_reg_id(RegType("i8*"), env.val_cnt);

        case NodeKind.ADD:
        case NodeKind.SUB:
        case NodeKind.MUL:
        case NodeKind.DIV:
        case NodeKind.REM:
            Reg lhs_reg = gen_llvm_ir_expr(env, node.lhs);
            Reg rhs_reg = gen_llvm_ir_expr(env, node.rhs);
            if(is_integer(lhs_reg) && is_integer(rhs_reg)) {
                assert(lhs_reg.type.str == rhs_reg.type.str);

                fprintf(env.fp, "  %%%d = ", ++env.val_cnt);
                switch(node.kind) {
                    case NodeKind.ADD: fprintf(env.fp, "add nsw "); break;
                    case NodeKind.SUB: fprintf(env.fp, "sub "); break;
                    case NodeKind.MUL: fprintf(env.fp, "mul nsw "); break;
                    case NodeKind.DIV: fprintf(env.fp, "sdiv "); break;
                    case NodeKind.REM: fprintf(env.fp, "srem "); break;
                    default: assert(0);
                }

                gen_llvm_ir_reg_with_type(env.fp, lhs_reg);

                if(rhs_reg.str is null)
                    fprintf(env.fp, ", %%%d\n", rhs_reg.id);
                else
                    fprintf(env.fp, ", %%%.*s\n", rhs_reg.str.length, rhs_reg.str.ptr);

                return make_reg_id(lhs_reg.type, env.val_cnt);
            } else if(is_pointer(lhs_reg) && is_integer(rhs_reg)) {
                if(node.kind == NodeKind.SUB)
                    rhs_reg = gen_llvm_ir_binop_const(env, "mul", rhs_reg, -1);
                return gen_llvm_ir_getelementptr_inbounds(env, lhs_reg, rhs_reg);
            } else if(is_integer(lhs_reg) && is_pointer(rhs_reg)) {
                assert(node.kind != NodeKind.SUB);

                return gen_llvm_ir_getelementptr_inbounds(env, rhs_reg, lhs_reg);
            } else if(is_pointer(lhs_reg) && is_pointer(rhs_reg)) {
                assert(node.kind != NodeKind.ADD);
                assert(lhs_reg.type.str == rhs_reg.type.str);

                return gen_llvm_ir_distance_of_pointers(env, lhs_reg, rhs_reg);
            } else {
                assert(0);
            }

        case NodeKind.EQ:
        case NodeKind.NE:
        case NodeKind.LT:
        case NodeKind.LE:
        case NodeKind.GT:
        case NodeKind.GE:
            Reg lhs_reg = gen_llvm_ir_expr(env, node.lhs);
            Reg rhs_reg = gen_llvm_ir_expr(env, node.rhs);
            Reg icmp_reg = gen_llvm_ir_icmp(env, node.kind, lhs_reg, rhs_reg);
            RegType ty = make_llvm_ir_reg_type(node.type);
            return gen_llvm_ir_integer_cast(env, ty, icmp_reg);

        case NodeKind.NOT:
            Reg lhs_reg = gen_llvm_ir_expr(env, node.lhs);
            assert(lhs_reg.type.str == "i8");
            return gen_llvm_ir_binop_const(env, "xor", lhs_reg, 1);

        case NodeKind.OROR:
            Reg lhs_reg = gen_llvm_ir_expr(env, node.lhs);
            Reg rhs_reg = gen_llvm_ir_expr(env, node.rhs);
            return gen_llvm_ir_binop(env, "or", lhs_reg, rhs_reg);

        case NodeKind.ANDAND:
            Reg lhs_reg = gen_llvm_ir_expr(env, node.lhs);
            Reg rhs_reg = gen_llvm_ir_expr(env, node.rhs);
            return gen_llvm_ir_binop(env, "and", lhs_reg, rhs_reg);

        case NodeKind.LVAR:
            RegType ty = make_llvm_ir_reg_type(node.type);
            gen_llvm_ir_load(env, make_reg_str(ref_reg_type(ty), node.token.str));
            return make_reg_id(ty, env.val_cnt);

        case NodeKind.FUNC_CALL:
            Reg[] arg_regs;
            foreach(arg; node.func_call_args) {
                arg_regs ~= gen_llvm_ir_expr(env, arg);
            }

            RegType ret_reg_type = make_llvm_ir_reg_type(node.type);

            if(ret_reg_type.str != "void") {
                fprintf(env.fp, "  %%%d = ", ++env.val_cnt);
            }

            fprintf(env.fp, "call %.*s @%.*s(",
                ret_reg_type.str.length, ret_reg_type.str.ptr,
                node.token.str.length, node.token.str.ptr,
            );
            foreach(i, e; arg_regs) {
                gen_llvm_ir_reg_with_type(env.fp, e);
                if(i != arg_regs.length -1)
                    fprintf(env.fp, ", ");
            }
            fprintf(env.fp, ")\n");

            if(ret_reg_type.str != "void")
                return make_reg_id(ret_reg_type, env.val_cnt);
            else
                return make_reg_id(ret_reg_type, -1);

        case NodeKind.ASSIGN:
            Reg lhs_reg = gen_llvm_ir_expr_lval(env, node.lhs);
            Reg rhs_reg = gen_llvm_ir_expr(env, node.rhs);
            gen_llvm_ir_store(env, rhs_reg, lhs_reg);
            gen_llvm_ir_load(env, lhs_reg);
            return make_reg_id(deref_reg_type(lhs_reg.type), env.val_cnt);

        case NodeKind.CAST:
            assert(is_integer_type(node.type) || is_pointer_type(node.type));

            Reg lhs_reg = gen_llvm_ir_expr(env, node.lhs);
            RegType ty = make_llvm_ir_reg_type(node.type);

            if(is_integer_type(node.type)) {
                if(node.type.str == "bool") {
                    assert(is_integer_type(node.lhs.type) || is_pointer_type(node.lhs.type));
                    auto i1_reg = gen_llvm_ir_icmp_ne_0(env, lhs_reg);
                    return gen_llvm_ir_integer_cast(env, ty, i1_reg);
                } else {
                    assert(is_integer_type(node.lhs.type));
                    return gen_llvm_ir_integer_cast(env, ty, lhs_reg);
                }
            } else if(is_pointer_type(node.type)) {
                assert(is_pointer_type(node.lhs.type));
                return gen_llvm_ir_pointer_cast(env, ty, lhs_reg);
            }
            assert(0);

        case NodeKind.DOT:
            assert(node.token.str == "sizeof");
            if(node.token.str == "sizeof") {
                RegType ty = make_llvm_ir_reg_type(node.type);
                fprintf(env.fp, "  %%%d = add %.*s 0, %d\n",
                    ++env.val_cnt,
                    ty.str.length, ty.str.ptr,
                    node.val);

                return make_reg_id(ty, env.val_cnt);
            }
            break;

        case NodeKind.INDEX:
            Reg lhs = gen_llvm_ir_expr(env, node.lhs);
            Reg idx = gen_llvm_ir_expr(env, node.index_expr1);
            Reg ptr = gen_llvm_ir_getelementptr_inbounds(env, lhs, idx);
            return gen_llvm_ir_load(env, ptr);

        case NodeKind.SLICE:
            assert(0);

        case NodeKind.PRE_INC:
        case NodeKind.PRE_DEC:
        case NodeKind.POST_INC:
        case NodeKind.POST_DEC:
            Reg lhs = gen_llvm_ir_expr_lval(env, node.lhs);
            Reg lhs_val = gen_llvm_ir_load(env, lhs);

            Reg lhs_inc;

            if(is_pointer(lhs_val)) {
                if(node.kind == NodeKind.PRE_INC || node.kind == NodeKind.POST_INC)
                    lhs_inc = gen_llvm_ir_getelementptr_inbounds_const(env, lhs_val, 1);
                else
                    lhs_inc = gen_llvm_ir_getelementptr_inbounds_const(env, lhs_val, -1);
            } else {
                if(node.kind == NodeKind.PRE_INC || node.kind == NodeKind.POST_INC)
                    lhs_inc = gen_llvm_ir_binop_const(env, "add", lhs_val, 1);
                else
                    lhs_inc = gen_llvm_ir_binop_const(env, "sub", lhs_val, 1);
            }

            gen_llvm_ir_store(env, lhs_inc, lhs);
            if(node.kind == NodeKind.PRE_INC || node.kind == NodeKind.PRE_DEC)
                return lhs_inc;
            else
                return lhs_val;

        case NodeKind.PTR_REF:
            Reg lhs = gen_llvm_ir_expr_lval(env, node.lhs);
            return lhs;

        case NodeKind.PTR_DEREF:
            Reg lhs = gen_llvm_ir_expr(env, node.lhs);
            assert(is_pointer(lhs));
            Reg lhs_val = gen_llvm_ir_load(env, lhs);
            return lhs_val;

        default:
            error("サポートしていないノードの種類です");
            break;
    }

    assert(0);
}


Reg gen_llvm_ir_expr_lval(LLVM_IR_Env* env, Node* node)
{
    switch(node.kind) {
        case NodeKind.PRE_INC:
        case NodeKind.PRE_DEC:
            Reg lhs = gen_llvm_ir_expr_lval(env, node.lhs);
            Reg lhs_val = gen_llvm_ir_load(env, lhs);

            Reg lhs_inc;
            if(is_pointer(lhs_val)) {
                if(node.kind == NodeKind.PRE_INC || node.kind == NodeKind.POST_INC)
                    lhs_inc = gen_llvm_ir_getelementptr_inbounds_const(env, lhs_val, 1);
                else
                    lhs_inc = gen_llvm_ir_getelementptr_inbounds_const(env, lhs_val, -1);
            } else {
                if(node.kind == NodeKind.PRE_INC || node.kind == NodeKind.POST_INC)
                    lhs_inc = gen_llvm_ir_binop_const(env, "add", lhs_val, 1);
                else
                    lhs_inc = gen_llvm_ir_binop_const(env, "sub", lhs_val, 1);
            }

            gen_llvm_ir_store(env, lhs_inc, lhs);
            return lhs;

        case NodeKind.PTR_DEREF:
            Reg lhs = gen_llvm_ir_expr(env, node.lhs);
            assert(is_pointer(lhs));
            return lhs;

        case NodeKind.INDEX:
            Reg lhs = gen_llvm_ir_expr(env, node.lhs);
            Reg idx = gen_llvm_ir_expr(env, node.index_expr1);
            return gen_llvm_ir_getelementptr_inbounds(env, lhs, idx);

        case NodeKind.LVAR:
            RegType ty = make_llvm_ir_reg_type(node.type);
            return make_reg_str(ref_reg_type(ty), node.token.str);
        
        case NodeKind.ASSIGN:
            Reg lhs_reg = gen_llvm_ir_expr_lval(env, node.lhs);
            Reg rhs_reg = gen_llvm_ir_expr(env, node.rhs);
            assert(deref_reg_type(lhs_reg.type).str == rhs_reg.type.str);
            gen_llvm_ir_store(env, rhs_reg, lhs_reg);
            return lhs_reg;

        default:
            error("左辺値が得られないノードの種類です");
            break;
    }

    return make_reg_str(RegType(null), null);
}


Reg gen_llvm_ir_alloca(LLVM_IR_Env* env, Type* ty, const(char)[] lvarname)
{
    Reg reg;
    reg.str = lvarname;
    reg.type = make_llvm_ir_reg_type(ty);

    fprintf(env.fp, "  %%%.*s = alloca %.*s, align %d\n",
        reg.str.length, reg.str.ptr,
        reg.type.str.length, reg.type.str.ptr,
        sizeof_type(ty)
        );

    reg.type = ref_reg_type(reg.type);
    return reg;
}


void gen_llvm_ir_store(LLVM_IR_Env* env, Reg src, Reg dst)
{
    if(!is_pointer(dst) || deref_reg_type(dst.type).str != src.type.str) {
        error("gen_llvm_ir_store: 型が一致しません． typeof(dst) = %.*s, typeof(src) = %.*s",
            dst.type.str.length, dst.type.str.ptr,
            src.type.str.length, src.type.str.ptr,
        );
    }

    fprintf(env.fp, "  store ");
    gen_llvm_ir_reg_with_type(env.fp, src);
    fprintf(env.fp, ", ");
    gen_llvm_ir_reg_with_type(env.fp, dst);
    fprintf(env.fp, ", align %d\n", sizeof_reg_type(src.type));
}


Reg gen_llvm_ir_load(LLVM_IR_Env* env, Reg src)
{
    ++env.val_cnt;

    if(!is_pointer(src)) {
        error("gen_llvm_ir_load: srcがポインタ型ではありません． typeof(src) = %.*s",
            src.type.str.length, src.type.str.ptr,
        );
    }

    string deref_type = deref_reg_type(src.type).str;
    fprintf(env.fp, "  %%%d = load %.*s, ",
        env.val_cnt,
        deref_type.length, deref_type.ptr,
    );
    gen_llvm_ir_reg_with_type(env.fp, src);
    fprintf(env.fp, ", align %d\n", sizeof_reg_type(src.type));

    Reg reg;
    reg.type.str = deref_type;
    reg.id = env.val_cnt;
    return reg;
}


Reg gen_llvm_ir_icmp(LLVM_IR_Env* env, NodeKind op_kind, Reg lhs_reg, Reg rhs_reg)
{
    assert(lhs_reg.type.str == rhs_reg.type.str);

    int result_i1_id = ++env.val_cnt;

    fprintf(env.fp, "  %%%d = icmp ", result_i1_id);

    switch(op_kind) {
        case NodeKind.EQ:
            fprintf(env.fp, "eq ");
            break;
        case NodeKind.NE:
            fprintf(env.fp, "ne ");
            break;
        case NodeKind.LT:
            fprintf(env.fp, "slt ");
            break;
        case NodeKind.LE:
            fprintf(env.fp, "sle ");
            break;
        case NodeKind.GT:
            fprintf(env.fp, "sgt ");
            break;
        case NodeKind.GE:
            fprintf(env.fp, "sge ");
            break;
        default:
            error("'op_kind = %d': 比較演算子ではありません", cast(int)op_kind);
            break;
    }

    gen_llvm_ir_reg_with_type(env.fp, lhs_reg);

    if(rhs_reg.str is null)
        fprintf(env.fp, ", %%%d\n", rhs_reg.id);
    else
        fprintf(env.fp, ", %%%.*s\n", rhs_reg.str.length, rhs_reg.str.ptr);

    return make_reg_id(RegType("i1"), result_i1_id);
}


Reg gen_llvm_ir_icmp_ne_0(LLVM_IR_Env* env, Reg lhs_reg)
{
    fprintf(env.fp, "  %%%d = icmp ne ", ++env.val_cnt);
    gen_llvm_ir_reg_with_type(env.fp, lhs_reg);
    if(is_pointer(lhs_reg))
        fprintf(env.fp, ", null\n");
    else
        fprintf(env.fp, ", 0\n");
    return make_reg_id(RegType("i1"), env.val_cnt);
}


void gen_llvm_ir_dummy_op(LLVM_IR_Env* env)
{
    fprintf(env.fp, "  %%%d = add i32 0, 0\n", ++env.val_cnt);
}


Reg gen_llvm_ir_integer_cast(LLVM_IR_Env* env, RegType ty, Reg val)
{
    assert(ty.str[0] == 'i');

    if(ty.str == val.type.str)
        return val;

    if(val.type.str == "i1") {
        fprintf(env.fp, "  %%%d = zext ", ++env.val_cnt);
        gen_llvm_ir_reg_with_type(env.fp, val);
        fprintf(env.fp, " to %.*s\n",
            ty.str.length, ty.str.ptr,
        );
        return make_reg_id(ty, env.val_cnt);
    }

    if(sizeof_reg_type(ty) < sizeof_reg_type(val.type)) {
        fprintf(env.fp, "  %%%d = trunc ", ++env.val_cnt);
        gen_llvm_ir_reg_with_type(env.fp, val);
        fprintf(env.fp, " to %.*s\n",
            ty.str.length, ty.str.ptr,
        );
    } else {
        fprintf(env.fp, "  %%%d = sext ", ++env.val_cnt);
        gen_llvm_ir_reg_with_type(env.fp, val);
        fprintf(env.fp, " to %.*s\n",
            ty.str.length, ty.str.ptr,
        );
    }

    return make_reg_id(ty, env.val_cnt);
}


Reg gen_llvm_ir_pointer_cast(LLVM_IR_Env* env, RegType ty, Reg val)
{
    fprintf(env.fp, "  %%%d = bitcast ", ++env.val_cnt);
    gen_llvm_ir_reg_with_type(env.fp, val);
    fprintf(env.fp, " to %.*s\n",
        ty.str.length, ty.str.ptr,
    );

    return make_reg_id(ty, env.val_cnt);
}


Reg gen_llvm_ir_binop_const(LLVM_IR_Env* env, string op, Reg val, long v)
{
    fprintf(env.fp, "  %%%d = %.*s ",
        ++env.val_cnt,
        op.length, op.ptr,
    );
    gen_llvm_ir_reg_with_type(env.fp, val);
    fprintf(env.fp, ", %lld\n", v);

    return make_reg_id(val.type, env.val_cnt);
}


Reg gen_llvm_ir_binop(LLVM_IR_Env* env, string op, Reg lhs, Reg rhs)
{
    assert(lhs.type.str == rhs.type.str);

    fprintf(env.fp, "  %%%d = %.*s ",
        ++env.val_cnt,
        op.length, op.ptr,
    );
    gen_llvm_ir_reg_with_type(env.fp, lhs);
    fprintf(env.fp, ", ");
    gen_llvm_ir_reg(env.fp, rhs);
    fprintf(env.fp, "\n");

    return make_reg_id(lhs.type, env.val_cnt);
}


Reg gen_llvm_ir_getelementptr_inbounds(LLVM_IR_Env* env, Reg ptr, Reg offset)
{
    RegType deref_type = deref_reg_type(ptr.type);

    fprintf(env.fp, "  %%%d = getelementptr inbounds %.*s, ",
        ++env.val_cnt,
        deref_type.str.length, deref_type.str.ptr,
    );
    gen_llvm_ir_reg_with_type(env.fp, ptr);
    fprintf(env.fp, ", ");
    gen_llvm_ir_reg_with_type(env.fp, offset);
    fprintf(env.fp, "\n");

    return make_reg_id(ptr.type, env.val_cnt);
}


Reg gen_llvm_ir_getelementptr_inbounds_const(LLVM_IR_Env* env, Reg ptr, long offset)
{
    RegType deref_type = deref_reg_type(ptr.type);

    fprintf(env.fp, "  %%%d = getelementptr inbounds %.*s, ",
        ++env.val_cnt,
        deref_type.str.length, deref_type.str.ptr,
    );
    gen_llvm_ir_reg_with_type(env.fp, ptr);
    fprintf(env.fp, ", i64 %lld\n", offset);

    return make_reg_id(ptr.type, env.val_cnt);
}


Reg gen_llvm_ir_ptr_to_i64(LLVM_IR_Env* env, Reg ptr)
{
    assert(is_pointer(ptr));

    fprintf(env.fp, "  %%%d = ptrtoint ", ++env.val_cnt);
    gen_llvm_ir_reg_with_type(env.fp, ptr);
    fprintf(env.fp, " to i64\n");

    return make_reg_id(RegType("i64"), env.val_cnt);
}


Reg gen_llvm_ir_distance_of_pointers(LLVM_IR_Env* env, Reg lhs, Reg rhs)
{
    Reg lhs_i64 = gen_llvm_ir_ptr_to_i64(env, lhs);
    Reg rhs_i64 = gen_llvm_ir_ptr_to_i64(env, rhs);
    Reg diff = gen_llvm_ir_binop(env, "sub", lhs_i64, rhs_i64);
    return gen_llvm_ir_binop_const(env, "sdiv exact", diff, sizeof_reg_type(deref_reg_type(lhs.type)));
}
