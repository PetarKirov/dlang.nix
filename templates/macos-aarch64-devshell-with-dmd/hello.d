#!/usr/bin/env rdmd
import std.stdio;

// TODO: Investigate why this workaround is needed
extern (C) __gshared bool rt_envvars_enabled = true;

void main()
{
    writeln("Hello, world!");
}
