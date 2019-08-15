extern(C):

enum TypeKind
{
    BASE,
    POINTER,
}

struct Type
{
    TypeKind kind;
    char[] str;
    Type* nested;
}
