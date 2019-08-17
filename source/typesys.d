extern(C):

enum TypeKind
{
    BASE,
    POINTER,
}

struct Type
{
    TypeKind kind;
    bool islval;
    const(char)[] str;
    Type* nested;
}


Type* make_basic_type(const(char)[] str)
{
    Type* ty = new Type;
    ty.kind = TypeKind.BASE;
    ty.islval = false;
    ty.str = str;
    ty.nested = null;
    return ty;
}


Type* make_bool_type()
{
    Type* ty = new Type;
    ty.kind = TypeKind.BASE;
    ty.islval = false;
    ty.str = "bool";
    ty.nested = null;
    return ty;
}


Type* make_int_type()
{
    Type* ty = new Type;
    ty.kind = TypeKind.BASE;
    ty.islval = false;
    ty.str = "int";
    ty.nested = null;
    return ty;
}


Type* make_void_type()
{
    Type* ty = new Type;
    ty.kind = TypeKind.BASE;
    ty.str = "void";
    ty.nested = null;
    return ty;
}

Type* make_pointer_type(Type* base)
{
    Type* ty = new Type;
    ty.kind = TypeKind.POINTER;
    ty.nested = base;
    ty.str = base.str ~ "*";
    return ty;
}


Type* make_void_pointer_type()
{
    return make_pointer_type(make_void_type());
}


bool is_same_type(Type* ty1, Type* ty2)
{
    if(ty1 is null || ty2 is null) return false;
    if(ty1.kind != ty2.kind) return false;

    if(ty1.kind == TypeKind.BASE)
        return ty1.str == ty2.str;
    else
        return is_same_type(ty1.nested, ty2.nested);
}


bool is_pointer_type(Type* ty)
{
    return ty.kind == TypeKind.POINTER;
}


bool is_integer_type(Type* ty)
{
    return ty.kind == TypeKind.BASE
        && (ty.str == "bool" || ty.str == "char" || ty.str == "byte" || ty.str == "short"
            || ty.str == "int" || ty.str == "long");
}


int sizeof_type(Type* ty)
{
    if(is_pointer_type(ty))
        return 8;

    if(ty.str == "bool")
        return 1;
    else if(ty.str == "char" || ty.str == "byte")
        return 1;
    else if(ty.str == "short")
        return 2;
    else if(ty.str == "int")
        return 4;
    else if(ty.str == "long")
        return 8;

    return -1;
}


Type* large_integer_type(Type* ty1, Type* ty2)
{
    if(sizeof_type(ty1) >= sizeof_type(ty2))
        return ty1;
    else
        return ty2;
}


Type* common_type_of(Type* ty1, Type* ty2)
{
    if(is_same_type(ty1, ty2))
        return ty1;

    if(is_integer_type(ty1) && is_integer_type(ty2))
        return large_integer_type(ty1, ty2);

    if(is_pointer_type(ty1) && is_pointer_type(ty2))
        return make_void_pointer_type();

    return null;
}


bool is_assignable_type(Type* ty1, Type* ty2)
{
    if(is_pointer_type(ty1) && is_pointer_type(ty2))
        return is_same_type(ty1, ty2) || is_same_type(ty1, make_void_pointer_type());

    if(is_integer_type(ty1) && is_integer_type(ty2))
        return sizeof_type(ty1) >= sizeof_type(ty2);

    return false;
}


bool is_compatible_type(Type* ty1, Type* ty2)
{
    return is_assignable_type(ty1, ty2);
}


bool is_auto_type(Type* ty)
{
    return ty.kind == TypeKind.BASE && ty.str == "auto";
}


// ty2をty1へ変換できるか？
bool is_castable_type(Type* ty1, Type* ty2)
{
    if(is_pointer_type(ty1) && is_pointer_type(ty2))
        return true;

    if(is_integer_type(ty1) && is_integer_type(ty2))
        return true;

    return false;
}
