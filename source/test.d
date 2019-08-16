import impl;

import std;

void main()
{
}


auto execute_lli(string ir)
{
    File file = File("tmp.ll", "w");
    file.write(ir);
    file.flush();

    auto lli = execute(["lli", file.name]);
    return lli;
}


auto get_ir(string code)
{
    File file = File.tmpfile();
    auto args = ["./tbc", code];
    auto cargs = args.map!(a => cast(char*)a.toStringz).array;

    Main(file.getFP, cast(int)args.length, cargs.ptr);
    file.flush();
    file.rewind;

    string ir;
    while(! file.eof)
        ir ~= file.readln();

    return ir;
}


unittest
{
    bool test(string input, int expected) {
        auto ir = get_ir("int main(){" ~ input ~ "}" );
        auto status = execute_lli(ir).status;
        return status == expected;
    }

    assert(test("return 0;", 0));
    assert(test("return 42;", 42));
    assert(test("return 5+20-4;", 21));
    assert(test("return 5+6*7;", 47));
    assert(test("return 5* (9 - 6);", 15));
    assert(test("return (3+5 ) /2;", 4));
    assert(test("return +5;", 5));
    assert(test("return 5+(-5);", 0));
    assert(test("return 5-5;", 0));
    assert(test("return 5-(+5);", 0));
    assert(test("return 5-(-(+5));", 10));
    assert(test("return -10+20;", 10));
    assert(test("return -0-10-20-(-10-20);", 0));
    assert(test("return 1 == 1;", 1));
    assert(test("return 1 != 1;", 0));
    assert(test("return 0 == 0;", 1));
    assert(test("return (1 == 1) == (3 == 3);", 1));
    assert(test("return (1 != 1) == (3 != 3);", 1));
    assert(test("return (1 > 0) == (3 > 0);", 1));
    assert(test("return (1 < 0) == (3 > 0);", 0));
    assert(test("return (1 <= 0) == (3 >= 0);", 0));
    assert(test("return 1>0;", 1));
    assert(test("return 0>0;", 0));
    assert(test("return 1>=0;", 1));
    assert(test("return 0>=0;", 1));
    assert(test("return -1>=0;", 0));
    assert(test("return 1<0;", 0));
    assert(test("return 0<0;", 0));
    assert(test("return -1<0;", 1));
    assert(test("return 1<=0;", 0));
    assert(test("return 0<=0;", 1));
    assert(test("return a=1;", 1));
    assert(test("return b=1;", 1));
    assert(test("int a=1; int b; return b=a*2;", 2));
    assert(test("int a=1; int b=a*2;return b=b*2;", 4));
    assert(test("int foo=1;int bar=foo*2;return bar=bar*2;", 4));
    assert(test("int _=1; int __=2; int _a=3; int a_b=4; return _+__+_a+a_b;", 10));
    assert(test("return 1;", 1));
    assert(test("int a = 12; return a+a; a+2;", 24));
    assert(test("int a = 1; if(1 == 1) a = 4; return a;", 4));
    assert(test("int a = 1; if(1 == 1) a = 4; else a = 8; return a;", 4));
    assert(test("int a=1; int b=2; if(1 == 0) b = 0; else a = 8; return a+b;", 10));
    assert(test("int a=1; if(1 == 0) a=2; else if(1 == 0) a=3; else a=4; return a;", 4));
    assert(test("int a=1; int b=0; if(1 == 0) { a=2; b=3; } else { a=3; b=4; } return a+b;", 7));
    assert(test(q{
        int a = 2;
        int b = 2;
        if(a == b) {
            if(a == b) {
                a = 4;
                b = 4;

                if(a == 3) {
                    a = 7;
                } else {
                    a = 5;
                }
            } else {}
        } else {

        }

        return a + b;
    }, 9));
    assert(test("int b=0; for(int a=1;a<10;a=a+1) { if(a > 5) b = b + a; } return b;", 30));
    assert(test("int a=0; for(;a<10;) { a = a + 1; } return a;", 10));
    assert(test("int c=0; for(int a=0;a<3;a=a+1) { for(int b=0;b<3;b=b+1) c = c + 1; } for(int a=0;a<10;a=a+1) {} return a+c;", 19));
    assert(test("int c=0; for(int a=0;a<10;a=a+1) { c=c+1; if(a==3) break; } return c;", 4));
    assert(test(q{
        int c = 0;
        for(int a = 0; a < 10; a = a + 1) {
            for(int b = 0; b < 10; b = b + 1){
                c = c + 1;
                if(b == 2)
                    break;
            }
        }
        return c;
    }, 30));
    assert(test("int a=0; for(;;){ a = a+1; if(a >= 10) return a; } 20;", 10));
    assert(test("int a=0; while(a<10) { a = a+1; } return a;", 10));
    assert(test("int a=0; while(1) { a = a+1; if(a >= 10) break; } return a;", 10));
    assert(test("int a; a = 10; return a;", 10));
}


// 関数呼び出しのテスト
unittest
{
    bool test_arg0(string input, int expected)
    {
        auto ir = get_ir("int main() { " ~ input ~ "}");
        ir ~= "\n";
        ir ~= "define i32 @foo() {\n";
        ir ~= "  ret i32 12\n";
        ir ~= "}\n";

        return execute_lli(ir).status == expected;
    }

    assert(test_arg0("return foo();", 12));
    assert(test_arg0("return foo() + foo() + 3;", 27));


    bool test_arg2(string input, int expected)
    {
        auto ir = get_ir("int main() { " ~ input ~ "}");
        ir ~= "\n";
        ir ~= "define i32 @foo(i32, i32) {\n";
        ir ~= "  %3 = add i32 %0, %1\n";
        ir ~= "  ret i32 %3\n";
        ir ~= "}\n";

        return execute_lli(ir).status == expected;
    }

    assert(test_arg2("return foo(1, 2);", 3));
    assert(test_arg2("return foo(foo(1, 2), foo(3, 4)) + foo(1, 2) + 3;", 16));
}

// 関数定義のテスト
unittest
{
    // フィボナッチ数列
    auto code = q{
        int fib(int n) {
            if(n == 0)
                return 0;
            else if(n == 1)
                return 1;
            else
                return fib(n-1) + fib(n-2);
        }

        int main() {
            return fib(12);
        }
    };

    assert(execute_lli(get_ir(code)).status == 144);
}