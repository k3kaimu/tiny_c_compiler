import impl;

import std;

void main()
{
}

unittest
{
    bool test(string input, int expected) {
        string filename = "tmp.ll";
        File file = File(filename, "w");
        auto args = ["./tbc", input];
        auto cargs = args.map!(a => cast(char*)a.toStringz).array;

        Main(file.getFP, cast(int)args.length, cargs.ptr);
        file.flush();
        auto lli = execute(["lli", filename]);

        if(lli.status == expected)
            return true;
        else{
            import std.stdio;
            writefln("Output: %s, Expected: %s", lli.status, expected);
            return false;
        }
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
}
