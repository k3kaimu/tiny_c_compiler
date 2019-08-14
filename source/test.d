import impl;

import std;

void main()
{
}

unittest
{
    bool test(int n) {
        string filename = "tmp.ll";
        File file = File(filename, "w");
        auto args = ["./tbc", n.to!string];
        auto cargs = args.map!(a => cast(char*)a.toStringz).array;

        Main(file.getFP, cast(int)args.length, cargs.ptr);
        file.flush();
        auto output = execute(["lli", filename]);
        return output.status == n;
    }

    assert(test(0));
    assert(test(42));
}
