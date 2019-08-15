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
        auto ir = get_ir(input);
        auto status = execute_lli(ir).status;
        return status == expected;
    }

    assert(test("0;", 0));
    assert(test("42;", 42));
    assert(test("5+20-4;", 21));
    assert(test("5+6*7;", 47));
    assert(test("5* (9 - 6);", 15));
    assert(test("(3+5 ) /2;", 4));
    assert(test("+5;", 5));
    assert(test("5+(-5);", 0));
    assert(test("5-5;", 0));
    assert(test("5-(+5);", 0));
    assert(test("5-(-(+5));", 10));
    assert(test("-10+20;", 10));
    assert(test("-0-10-20-(-10-20);", 0));
    assert(test("1 == 1;", 1));
    assert(test("1 != 1;", 0));
    assert(test("0 == 0;", 1));
    assert(test("(1 == 1) == (3 == 3);", 1));
    assert(test("(1 != 1) == (3 != 3);", 1));
    assert(test("(1 > 0) == (3 > 0);", 1));
    assert(test("(1 < 0) == (3 > 0);", 0));
    assert(test("(1 <= 0) == (3 >= 0);", 0));
    assert(test("1>0;", 1));
    assert(test("0>0;", 0));
    assert(test("1>=0;", 1));
    assert(test("0>=0;", 1));
    assert(test("-1>=0;", 0));
    assert(test("1<0;", 0));
    assert(test("0<0;", 0));
    assert(test("-1<0;", 1));
    assert(test("1<=0;", 0));
    assert(test("0<=0;", 1));
    assert(test("a=1;", 1));
    assert(test("b=1;", 1));
    assert(test("a=1;b=a*2;", 2));
    assert(test("a=1;b=a*2;b=b*2;", 4));
    assert(test("foo=1;bar=foo*2;bar=bar*2;", 4));
    assert(test("_=1; __=2; _a=3; a_b=4; _+__+_a+a_b;", 10));
    assert(test("return 1;", 1));
    assert(test("a = 12; return a+a; a+2;", 24));
    assert(test("a = 1; if(1 == 1) a = 4; a;", 4));
    assert(test("a = 1; if(1 == 1) a = 4; else a = 8; a;", 4));
    assert(test("a=1; b=2; if(1 == 0) b = 0; else a = 8; a+b;", 10));
    assert(test("a=1; if(1 == 0) a=2; else if(1 == 0) a=3; else a=4; a;", 4));
    assert(test("a=1;b=0; if(1 == 0) { a=2; b=3; } else { a=3; b=4; } a+b;", 7));
    assert(test(q{
        a = 2;
        b = 2;
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

        a + b;
    }, 9));
    assert(test("b=0; for(a=1;a<10;a=a+1) { if(a > 5) b = b + a; } b;", 30));
    assert(test("a=0; for(;a<10;) { a = a + 1; } a;", 10));
    assert(test("c=0; for(a=0;a<3;a=a+1) { for(b=0;b<3;b=b+1) c = c + 1; } for(a=0;a<10;a=a+1) {} a+c;", 19));
    assert(test("c=0; for(a=0;a<10;a=a+1) { c=c+1; if(a==3) break; } c;", 4));
    assert(test(q{
        c = 0;
        for(a = 0; a < 10; a = a + 1) {
            for(b = 0; b < 10; b = b + 1){
                c = c + 1;
                if(b == 2)
                    break;
            }
        }
        c;
    }, 30));
    assert(test("a=0; for(;;){ a = a+1; if(a >= 10) return a; } 20;", 10));
    assert(test("a=0; while(a<10) { a = a+1; } a;", 10));
    assert(test("a=0; while(1) { a = a+1; if(a >= 10) break; } a;", 10));
}

// 関数呼び出しのテスト
unittest
{
    bool test_arg0(string input, int expected)
    {
        auto ir = get_ir(input);
        ir ~= "\n";
        ir ~= "define i32 @foo() {\n";
        ir ~= "  ret i32 12\n";
        ir ~= "}\n";

        return execute_lli(ir).status == expected;
    }

    assert(test_arg0("foo();", 12));
    assert(test_arg0("foo() + foo() + 3;", 27));


    bool test_arg2(string input, int expected)
    {
        auto ir = get_ir(input);
        ir ~= "\n";
        ir ~= "define i32 @foo(i32, i32) {\n";
        ir ~= "  %3 = add i32 %0, %1\n";
        ir ~= "  ret i32 %3\n";
        ir ~= "}\n";

        return execute_lli(ir).status == expected;
    }

    assert(test_arg2("foo(1, 2);", 3));
    assert(test_arg2("foo(foo(1, 2), foo(3, 4)) + foo(1, 2) + 3;", 16));
}
