import ast;
import typesys;
import tokenizer;
import utils;

Node* lookup_function(Node*[] program, const(char)[] name)
{
    foreach(p; program) {
        if(p.token.str == name)
            return p;
    }

    return null;
}


struct BlockEnv
{
    BlockEnv* parent;
    bool is_loop;
    Variable[] var_defs;
}


Variable lookup_variable(BlockEnv* env, const(char)[] name)
{
    if(env is null)
        return Variable(null, null);

    foreach(e; env.var_defs)
        if(e.token.str == name)
            return e;

    return lookup_variable(env.parent, name);
}


bool is_breakable(BlockEnv* env)
{
    if(env is null)
        return false;

    if(env.is_loop)
        return true;

    return is_breakable(env.parent);
}


void semantic_analysis(Node*[] program)
{
    BlockEnv* env = new BlockEnv;
    foreach(func; program) {
        assert(func.kind == NodeKind.FUNC_DEF);

        BlockEnv* new_env = new BlockEnv;
        foreach(e; func.func_def_args)
            new_env.var_defs ~= e;

        foreach(s; func.func_def_body)
            semantic_analysis_node(s, new_env, func, program);
    }
}


Node* new_node_cast_with_check(Type* type, Node* from)
{
    if(type is null) {
        error("変換先の型が不定です");
    }

    if(from.type is null) {
        error("変換元の型が不定です");
    }

    if(!is_castable_type(type, from.type)) {
        error("型 '%.*s' を '%.*s' に変換できません",
            from.type.str.length, from.type.str.ptr,
            type.str.length, type.str.ptr,
        );
    }

    return new_node_cast(type, from);
}


void semantic_analysis_node(Node* node, BlockEnv* env, Node* func, Node*[] program)
{
    if(node is null)
        return;

    final switch(node.kind) {
        case NodeKind.ADD:
        case NodeKind.SUB:
        case NodeKind.MUL:
        case NodeKind.DIV:
        case NodeKind.REM:
            semantic_analysis_node(node.lhs, env, func, program);
            semantic_analysis_node(node.rhs, env, func, program);

            Type* comty = common_type_of(node.lhs.type, node.rhs.type);

            if(!is_same_type(node.lhs.type, comty))
                node.lhs = new_node_cast_with_check(comty, node.lhs);

            if(!is_same_type(node.rhs.type, comty))
                node.rhs = new_node_cast_with_check(comty, node.rhs);

            node.type = comty;
            return;

        case NodeKind.EQ:
        case NodeKind.NE:
        case NodeKind.LT:
        case NodeKind.LE:
        case NodeKind.GT:
        case NodeKind.GE:
            semantic_analysis_node(node.lhs, env, func, program);
            semantic_analysis_node(node.rhs, env, func, program);

            Type* comty = common_type_of(node.lhs.type, node.rhs.type);

            if(!is_same_type(node.lhs.type, comty))
                node.lhs = new_node_cast_with_check(comty, node.lhs);
            if(!is_same_type(node.rhs.type, comty))
                node.rhs = new_node_cast_with_check(comty, node.rhs);

            node.type = make_bool_type();
            return;
        
        case NodeKind.ASSIGN:
            semantic_analysis_node(node.lhs, env, func, program);
            semantic_analysis_node(node.rhs, env, func, program);

            if(!node.lhs.type.islval)
                error("右辺値に代入できません");

            if(!is_assignable_type(node.lhs.type, node.rhs.type)) {
                error("型 '%.*s' に 型 '%.*s' の値は代入できません",
                    node.lhs.type.str.length, node.lhs.type.str.ptr,
                    node.rhs.type.str.length, node.rhs.type.str.ptr,
                );
            }

            if(!is_same_type(node.lhs.type, node.rhs.type))
                node.rhs = new_node_cast_with_check(node.lhs.type, node.rhs);

            node.type = node.lhs.type;
            node.type.islval = true;
            return;

        case NodeKind.CAST:
            semantic_analysis_node(node.lhs, env, func, program);
            return;

        case NodeKind.LVAR:
            Variable def = lookup_variable(env, node.token.str);
            if(def.type is null || def.token is null) {
                error("'%.*s': 未定義の変数です",
                    node.token.str.length, node.token.str.ptr);
            }

            node.type = def.type;
            node.type.islval = true;
            return;

        case NodeKind.NUM:
            node.type = make_int_type();
            return;

        case NodeKind.FUNC_CALL:
            Node* def = lookup_function(program, node.token.str);
            if(def is null) {
                error_at(node.token.str.ptr, "関数 '%.*s' は未定義です",
                    node.token.str.length, node.token.str.ptr,
                );
            }

            foreach(i; 0 .. node.func_call_args.length) {
                semantic_analysis_node(node.func_call_args[i], env, func, program);

                Node* call_arg = node.func_call_args[i];
                Type* call_type = call_arg.type;
                Type* def_type = def.func_def_args[i].type;

                semantic_analysis_node(call_arg, env, func, program);
                if(!is_compatible_type(def_type, call_type)) {
                    error_at(node.token.str.ptr, "関数'%.*s'の第%d引数の型は '%.*s' ですが '%.*s' で呼び出されています",
                        def.token.str.length, def.token.str.ptr,
                        def_type.str.length, def_type.str.ptr,
                        call_type.str.length, call_type.str.ptr,
                    );
                }

                if(!is_same_type(def_type, call_type))
                    node.func_call_args[i] = new_node_cast_with_check(def_type, call_arg);
            }

            node.type = def.ret_type;
            return;
        
        case NodeKind.DOT:
            if(node.token.str == "sizeof") {
                semantic_analysis_node(node.lhs, env, func, program);
                node.type = make_int_type();
                node.val = sizeof_type(node.lhs.type);
                return;
            }
            assert(0);
            break;
        case NodeKind.EXPR_STMT:
            semantic_analysis_node(node.lhs, env, func, program);
            return;

        case NodeKind.BLOCK:
            BlockEnv* new_env = new BlockEnv;
            new_env.parent = env;
            foreach(e; node.stmts)
                semantic_analysis_node(e, new_env, func, program);
            return;

        case NodeKind.RETURN:
            semantic_analysis_node(node.lhs, env, func, program);
            Type* ret_type = func.ret_type;
            Type* val_type = node.lhs.type;
            if(!is_compatible_type(ret_type, val_type)) {
                error("関数 '%.*s' の戻り値の型は '%.*s' です．型 '%.*s' の値を返せません",
                    func.token.str.length, func.token.str.ptr,
                    ret_type.str.length, ret_type.str.ptr,
                    val_type.str.length, val_type.str.ptr,
                );
            }

            if(!is_same_type(ret_type, val_type))
                node.lhs = new_node_cast_with_check(ret_type, node.lhs);

            return;

        case NodeKind.IF:
        case NodeKind.IFELSE:
            BlockEnv* new_env = new BlockEnv;
            new_env.parent = env;
            semantic_analysis_node(node.cond, new_env, func, program);
            semantic_analysis_node(node.thenblock, new_env, func, program);
            
            if(node.elseblock !is null) {
                new_env = new BlockEnv;
                new_env = env;
                semantic_analysis_node(node.elseblock, new_env, func, program);
            }

            if(is_integer_type(node.cond.type))
                return;

            if(is_pointer_type(node.cond.type)) {
                node.cond = new_node_cast_with_check(make_bool_type(), node.cond);
                return;
            }

            error("式を整数型に変換できません");
            return;

        case NodeKind.FOR:
            BlockEnv* new_env = new BlockEnv;
            new_env.parent = env;
            new_env.is_loop = true;
            semantic_analysis_node(node.init_stmt, new_env, func, program);
            semantic_analysis_node(node.cond, new_env, func, program);
            semantic_analysis_node(node.update_expr, new_env, func, program);
            semantic_analysis_node(node.thenblock, new_env, func, program);

            if(is_integer_type(node.cond.type))
                return;

            if(is_pointer_type(node.cond.type)) {
                node.cond = new_node_cast_with_check(make_bool_type(), node.cond);
                return;
            }

            error("式を整数型に変換できません");
            return;

        case NodeKind.FOREACH:
            BlockEnv* new_env = new BlockEnv;
            new_env.parent = env;
            new_env.is_loop = true;
            semantic_analysis_node(node.def_loop_var, new_env, func, program);
            semantic_analysis_node(node.start_expr, new_env, func, program);
            semantic_analysis_node(node.end_expr, new_env, func, program);
            semantic_analysis_node(node.thenblock, new_env, func, program);

            Type* var_type = node.def_loop_var.def_var.type;
            Type* start_expr_type = node.start_expr.type;
            Type* end_expr_type = node.end_expr.type;

            if(!is_same_type(var_type, start_expr_type))
                node.start_expr = new_node_cast_with_check(var_type, node.start_expr);

            if(!is_same_type(var_type, end_expr_type))
                node.end_expr = new_node_cast_with_check(var_type, node.end_expr);
            return;

        case NodeKind.BREAK:
            if(!is_breakable(env)) {
                error("ループの外なのでbreakできません");
            }
            return;

        case NodeKind.SIZEOF:
            semantic_analysis_node(node.lhs, env, func, program);
            node.type = make_int_type();
            node.val = sizeof_type(node.lhs.type);
            return;

        case NodeKind.FUNC_DEF:
            error("関数定義の中に関数定義を含めることはできません");
            return;

        case NodeKind.TYPE:
            return;
        
        case NodeKind.LVAR_DEF:
            if(node.lhs !is null) {
                semantic_analysis_node(node.lhs, env, func, program);

                if(is_auto_type(node.def_var.type))
                    node.def_var.type = node.lhs.type;

                if(!is_compatible_type(node.def_var.type, node.lhs.type)) {
                    error_at(node.token.str.ptr, "型 '%.*s' の値で 型 '%.*s' の変数を初期化できません",
                        node.lhs.type.str.length, node.lhs.type.str.ptr,
                        node.def_var.type.str.length, node.def_var.type.str.ptr,
                    );
                }

                if(!is_same_type(node.def_var.type, node.lhs.type))
                    node.lhs = new_node_cast_with_check(node.def_var.type, node.lhs);
            }

            if(is_auto_type(node.def_var.type)) {
                error_at(node.token.str.ptr, "型が未決定です");
            }

            env.var_defs ~= node.def_var;
            return;
    }
}
