module dlang_nix.utils.ranges;

import std.algorithm : find, map;
import std.range.primitives : ElementType, front, empty;

auto firstOrDefault
    (alias predicate, Range)
    (Range r, ElementType!Range default_ = ElementType!Range.init)
{
    auto res = r.find!predicate;
    return res.empty ? default_ : res.front;
}

V* tryGet(K, V)(V[K] aa, K[] keys...) => keys
    .map!(k => k in aa)
    .firstOrDefault!"!!a";
