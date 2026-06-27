module dlang_nix.utils.conv;

import std.conv : ConvException;
import std.traits : EnumMembers;

@safe:

/// Parses a string into enum `E` by matching member *values*. Unlike
/// `std.conv.to!E`, which matches member *names*, this suits string-backed enums
/// whose value differs from the identifier (e.g. `NixSystem.x86_64_linux ==
/// "x86_64-linux"`). The `static foreach` expands one `case` per member, so the
/// compiler builds a string switch.
E parseEnum(E)(string s) pure if (is(E == enum)) {
    switch (s) {
        static foreach (member; EnumMembers!E)
    case member:
            return member;
    default:
        throw new ConvException("invalid " ~ E.stringof ~ ": " ~ s);
    }
}

@("dlang_nix.utils.conv.parseEnum")
unittest {
    enum Color : string {
        red = "red",
        deepBlue = "deep-blue",
    }

    assert(parseEnum!Color("red") == Color.red);
    assert(parseEnum!Color("deep-blue") == Color.deepBlue);

    import std.exception : assertThrown;

    assertThrown!ConvException(parseEnum!Color("deepBlue")); // matches value, not name
    assertThrown!ConvException(parseEnum!Color("green"));
}
