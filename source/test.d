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


bool test_with_report(string ir, int expected)
{
    auto lli = execute_lli(ir);
    if(lli.status == expected)
        return true;

    writeln("Unittest is failed.");
    writefln("lli status: %s", lli.status);
    writefln("lli output:\n%s", lli.output);
    writefln("generated LLVM-IR:\n%s", ir);
    return false;
}


unittest
{
    bool test(string input, int expected) {
        auto ir = get_ir("int main(){" ~ input ~ "}" );
        return test_with_report(ir, expected);
    }

    assert(test("return 0;", 0));
    assert(test("return 42;", 42));
    assert(test("return 5+20-4;", 21));
    assert(test("return 5+6*7;", 47));
    assert(test("return 5* (9 - 6);", 15));
    assert(test("return (3+5 ) /2;", 4));
    assert(test("return 7 % 3;", 1));
    assert(test("return 8 % 3;", 2));
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
    assert(test("int a; return a=1;", 1));
    assert(test("int a; int b; return a=b=1;", 1));
    assert(test("int a=1; int b; return b=a*2;", 2));
    assert(test("int a=1; int b=a*2;return b=b*2;", 4));
    assert(test("int foo=1;int bar=foo*2;return bar=bar*2;", 4));
    assert(test("int _=1; int __=2; int _a=3; int a_b=4; return _+__+_a+a_b;", 10));
    assert(test("return 1;", 1));
    assert(test("int a = 12; return a+a; a+2;", 24));
    assert(test("int a = 12; int b = ++a; return b + a;", 26));
    assert(test("int a = 12; int b = a++; return b + a;", 25));
    assert(test("int a = 12; int b = ++ ++a; return b + a;", 28));
    assert(test("int a = 12; int b = (++a)++; return b + a;", 27));
    assert(test("int a = 12; ++((++a) = 14); return a;", 15));
    assert(test("int a = 12; int b = --a; return b + a;", 22));
    assert(test("int a = 12; int b = a--; return b + a;", 23));
    assert(test("int a = 12; int b = -- --a; return b + a;", 20));
    assert(test("int a = 12; int b = (--a)--; return b + a;", 21));
    assert(test("int a = 12; --((--a) = 14); return a;", 13));
    assert(test("int a; int b; a = b = 12; return a + b;", 24));
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
    assert(test("int c=0; for(int a=0;a<3;a=a+1) { for(int b=0;b<3;b=b+1) c = c + 1; } int a; for(a=0;a<10;a=a+1) {} return a+c;", 19));
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
    assert(test("int b = 0; foreach(int a; 0 .. 11) { b = b + a; } return b;", 55));
    assert(test("int a = 11; int b = 0; foreach(int i; 0 .. a) { a = i; b = b + i; } return b;", 55));
    assert(test("short a = cast(short)12; return a;", 12));
    assert(test("auto a = 12; auto b = a; return a + b;", 24));
    assert(test("auto a = 12; return a.sizeof;", 4));
    assert(test("long a = 12; return a.sizeof;", 8));
    assert(test("char a; return a.sizeof;", 1));
    assert(test("short a; return a.sizeof;", 2));
    assert(test("int a; return a.sizeof;", 4));
    assert(test("char a; auto b = a; return b.sizeof;", 1));
    assert(test("char a = cast(char)255; a = a + cast(char)1; a = a + cast(char)10; return a;", 10));
    assert(test("long a = 1; foreach(int i; 0 .. 100) if(i % 2 != 0) a = a * i; return cast(int)(a % 64);", 35));
    assert(test("int a; auto p = &a; return p.sizeof;", 8));
    assert(test("int a; auto p = &a; *p = 12; return *p;", 12));
    assert(test("int a; auto p = &a; auto pp = &p; **pp = 12; return **pp;", 12));
    assert(test("int a; int b; return &a == &a;", 1));
    assert(test("int a; int b; return &a != &a;", 0));
    assert(test("int a; int b; return &a != &b;", 1));
    assert(test("int a; int b; return &a == &b;", 0));
}


// 関数呼び出しのテスト
unittest
{
    bool test_arg0(string input, int expected)
    {
        auto ir = get_ir("int main() { " ~ input ~ "} int foo() { return 12; }");
        return test_with_report(ir, expected);
    }

    assert(test_arg0("return foo();", 12));
    assert(test_arg0("return foo() + foo() + 3;", 27));


    bool test_arg2(string input, int expected)
    {
        auto ir = get_ir("int main() { " ~ input ~ "} int foo(int a, int b) { return a + b; }");
        return test_with_report(ir, expected);
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

    assert(test_with_report(get_ir(code), 144));
}