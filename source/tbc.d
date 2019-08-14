// extern(C):

import core.runtime;
import std.stdio;
import impl;

int main()
{
    return Main(stdout.getFP, Runtime.cArgs.tupleof);
}
