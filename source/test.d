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

    assert(test("0", 0));
    assert(test("42", 42));
    assert(test("5+20-4", 21));
}
