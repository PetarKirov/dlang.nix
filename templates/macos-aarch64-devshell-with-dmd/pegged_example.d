#!/usr/bin/env dub
/+dub.sdl:
dependency "pegged" version="~>0.4"
+/
import pegged.grammar;
import std.stdio;

// TODO: Investigate why this workaround is needed
extern (C) __gshared bool rt_envvars_enabled = true;

mixin(grammar(`
Arithmetic:
    Term     < Factor (Add / Sub)*
    Add      < "+" Factor
    Sub      < "-" Factor
    Factor   < Primary (Mul / Div)*
    Mul      < "*" Primary
    Div      < "/" Primary
    Primary  < Parens / Neg / Pos / Number / Variable
    Parens   < "(" Term ")"
    Neg      < "-" Primary
    Pos      < "+" Primary
    Number   < ~([0-9]+)

    Variable <- identifier
`));

void main()
{
    // Parsing at compile-time:
    enum parseTree1 = Arithmetic("1 + 2 - (3*x-5)*6");

    pragma(msg, parseTree1.matches);
    assert(parseTree1.matches == ["1", "+", "2", "-",
       "(", "3", "*", "x", "-", "5", ")", "*", "6"]);
    writeln(parseTree1);

    // And at runtime too:
    auto parseTree2 = Arithmetic(" 0 + 123 - 456 ");
    assert(parseTree2.matches == ["0", "+", "123", "-", "456"]);
}
