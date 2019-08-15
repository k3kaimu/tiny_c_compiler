import impl;

import std;

void main()
{
}

unittest
{
    bool test(string input, int output) {
        string filename = "tmp.ll";
        File file = File(filename, "w");
        auto args = ["./tbc", input];
        auto cargs = args.map!(a => cast(char*)a.toStringz).array;

        Main(file.getFP, cast(int)args.length, cargs.ptr);
        file.flush();
        auto lli = execute(["lli", filename]);
        return lli.status == output;
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
}
