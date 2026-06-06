module dlang_nix.utils.json;

import std.algorithm : map, sort;
import std.array : appender, array, join;
import std.conv : to;
import std.format : format;
import std.json : JSONValue, JSONType, parseJSON;
import std.string : outdent;
import std.uni : isControl;

import sparkles.versions : SemVer;

import dlang_nix.components : Platform, Version;
import dlang_nix.utils.commands : Hash;

/// Converts a `Hash[Platform][Version]` AA into a JSONValue, mapping null
/// or empty Hash values to JSON `null`. Done manually because D's std.json
/// otherwise renders a null `string` as the JSON string `""`, masking the
/// "unsupported on this platform" sentinel.
JSONValue hashesToJsonValue(Hash[Platform][Version] hashes) {
    JSONValue[string] outer;
    foreach (ver, platforms; hashes) {
        JSONValue[string] inner;
        foreach (platform, hash; platforms) {
            inner[platform] = hash.length == 0 ? JSONValue(null) : JSONValue(hash);
        }
        outer[ver] = JSONValue(inner);
    }
    return JSONValue(outer);
}

/// Parses `existingJson` (if non-empty), merges `newHashes` into it, and
/// returns the result rendered as pretty JSON with a trailing newline.
/// New entries overwrite existing version/platform pairs. Existing `null`
/// or `""` entries are preserved as the null sentinel.
string mergeHashesIntoJson(string existingJson, Hash[Platform][Version] newHashes) {
    Hash[Platform][Version] allHashes;
    if (existingJson.length > 0) {
        auto existing = parseJSON(existingJson);
        foreach (string ver, platforms; existing.object) {
            foreach (string platform, hashVal; platforms.object) {
                if (hashVal.type == JSONType.null_ || hashVal.str.length == 0) {
                    allHashes[ver][platform] = cast(Hash) null;
                } else {
                    allHashes[ver][platform] = hashVal.str;
                }
            }
        }
    }
    foreach (ver, platforms; newHashes) {
        foreach (platform, hash; platforms) {
            allHashes[ver][platform] = hash;
        }
    }
    return toSortedPrettyJson(hashesToJsonValue(allHashes)) ~ "\n";
}

// `outdent` strips the leading whitespace common to every non-blank line,
// letting the JSON literals below be indented for readability. `[1 .. $]`
// drops the leading newline that the backtick-on-its-own-line syntax adds.

// editorconfig-checker-disable
unittest {
    // Empty existing JSON: only new hashes appear.
    Hash[Platform][Version] h1;
    h1["1.0.0"]["linux"] = "sha256-abc";
    assert(mergeHashesIntoJson("", h1) == outdent(`
        {
          "1.0.0": {
            "linux": "sha256-abc"
          }
        }
    `)[1 .. $]);

    // Non-overlapping versions are unioned.
    Hash[Platform][Version] h2;
    h2["2.0.0"]["linux"] = "sha256-new";
    assert(mergeHashesIntoJson(
        `{"1.0.0": {"linux": "sha256-old"}}`, h2) == outdent(`
        {
          "1.0.0": {
            "linux": "sha256-old"
          },
          "2.0.0": {
            "linux": "sha256-new"
          }
        }
    `)[1 .. $]);

    // Overlapping version/platform: new value overwrites existing.
    Hash[Platform][Version] h3;
    h3["1.0.0"]["linux"] = "sha256-new";
    assert(mergeHashesIntoJson(
        `{"1.0.0": {"linux": "sha256-old"}}`, h3) == outdent(`
        {
          "1.0.0": {
            "linux": "sha256-new"
          }
        }
    `)[1 .. $]);

    // Same version, disjoint platforms: platforms are merged and sorted.
    Hash[Platform][Version] h4;
    h4["1.0.0"]["osx"] = "sha256-osx";
    assert(mergeHashesIntoJson(
        `{"1.0.0": {"linux": "sha256-linux"}}`, h4) == outdent(`
        {
          "1.0.0": {
            "linux": "sha256-linux",
            "osx": "sha256-osx"
          }
        }
    `)[1 .. $]);

    // Null Hash from a failed prefetch renders as JSON null, not `""`.
    Hash[Platform][Version] h5;
    h5["1.0.0"]["linux"] = "sha256-linux";
    h5["1.0.0"]["freebsd"] = null;
    assert(mergeHashesIntoJson("", h5) == outdent(`
        {
          "1.0.0": {
            "freebsd": null,
            "linux": "sha256-linux"
          }
        }
    `)[1 .. $]);

    // Legacy `""` entries in existing JSON are normalized to JSON null.
    Hash[Platform][Version] h6;
    assert(mergeHashesIntoJson(
        `{"1.0.0": {"linux": "sha256-linux", "freebsd": ""}}`, h6) == outdent(`
        {
          "1.0.0": {
            "freebsd": null,
            "linux": "sha256-linux"
          }
        }
    `)[1 .. $]);
}
// editorconfig-checker-enable

/// Escapes a string for embedding in a JSON document. Forward slashes are
/// deliberately left unescaped (matching std.json's `doNotEscapeSlashes`);
/// every other JSON string metacharacter — quotes, backslashes and control
/// characters — is escaped so arbitrary input always yields valid JSON.
@safe pure string escapeJsonString(string s) {
    auto app = appender!string;
    foreach (dchar c; s) {
        switch (c) {
            case '"': app.put(`\"`); break;
            case '\\': app.put(`\\`); break;
            case '\b': app.put(`\b`); break;
            case '\f': app.put(`\f`); break;
            case '\n': app.put(`\n`); break;
            case '\r': app.put(`\r`); break;
            case '\t': app.put(`\t`); break;
            default:
                if (isControl(c))
                    app.put(format(`\u%04x`, cast(uint) c));
                else
                    app.put(c);
                break;
        }
    }
    return app.data;
}

/// Renders a JSONValue as pretty-printed JSON. Object keys are sorted
/// SemVer-aware when they parse as versions and lexically otherwise. String
/// values are escaped via `escapeJsonString` (forward slashes excepted).
@safe pure string toSortedPrettyJson(JSONValue val, string indent = "") {
    final switch (val.type) {
        case JSONType.null_:
            return "null";
        case JSONType.true_:
            return "true";
        case JSONType.false_:
            return "false";
        case JSONType.integer:
            return val.integer.to!string;
        case JSONType.uinteger:
            return val.uinteger.to!string;
        case JSONType.float_:
            return val.floating.to!string;
        case JSONType.string:
            return `"` ~ escapeJsonString(val.str) ~ `"`;
        case JSONType.array:
            auto arr = val.arrayNoRef;
            if (arr.length == 0) return "[]";
            auto inner = indent ~ "  ";
            auto items = arr.map!(item =>
                format(`%s%s`, inner, toSortedPrettyJson(item, inner))
            ).join(",\n");
            return format("[\n%s\n%s]", items, indent);
        case JSONType.object:
            auto obj = val.objectNoRef;
            auto keys = obj.keys.sort!((a, b) {
                auto va = SemVer.parseLoose(a);
                auto vb = SemVer.parseLoose(b);
                if (va.hasValue && vb.hasValue) {
                    return va.value < vb.value;
                }
                if (va.hasValue != vb.hasValue) {
                    return va.hasValue;
                }
                return a < b;
            }).release;
            if (keys.length == 0) return "{}";
            auto inner = indent ~ "  ";
            auto items = keys.map!(k =>
                format(`%s"%s": %s`, inner, escapeJsonString(k), toSortedPrettyJson(obj[k], inner))
            ).join(",\n");
            return format("{\n%s\n%s}", items, indent);
    }
}

// editorconfig-checker-disable
unittest {
    import std.json : parseJSON;

    // Scalars
    assert(toSortedPrettyJson(JSONValue(null)) == "null");
    assert(toSortedPrettyJson(JSONValue(true)) == "true");
    assert(toSortedPrettyJson(JSONValue(false)) == "false");
    assert(toSortedPrettyJson(JSONValue(42)) == "42");
    assert(toSortedPrettyJson(JSONValue("hi")) == `"hi"`);

    // Forward slashes are not escaped.
    assert(toSortedPrettyJson(JSONValue("a/b/c")) == `"a/b/c"`);

    // Quotes, backslashes and control chars are escaped.
    assert(toSortedPrettyJson(JSONValue(`a"b\c`)) == `"a\"b\\c"`);
    assert(toSortedPrettyJson(JSONValue("tab\there")) == `"tab\there"`);
    assert(toSortedPrettyJson(JSONValue("line\nbreak")) == `"line\nbreak"`);
    assert(toSortedPrettyJson(JSONValue("\x01")) == `"\u0001"`);

    // Empty containers render inline.
    assert(toSortedPrettyJson(parseJSON(`{}`)) == "{}");
    assert(toSortedPrettyJson(parseJSON(`[]`)) == "[]");

    // Object keys are emitted in sorted order.
    assert(toSortedPrettyJson(parseJSON(`{"b": "1", "a": "2"}`)) == outdent(`
        {
          "a": "2",
          "b": "1"
        }`)[1 .. $]);

    // Object keys are sorted by SemVer if they parse as versions.
    assert(toSortedPrettyJson(parseJSON(`{"1.40.0": "1", "1.4.0": "2"}`)) == outdent(`
        {
          "1.4.0": "2",
          "1.40.0": "1"
        }`)[1 .. $]);

    // Handles DMD version strings correctly.
    assert(toSortedPrettyJson(parseJSON(`{"2.100.0": "1", "2.070.2": "2"}`)) == outdent(`
        {
          "2.070.2": "2",
          "2.100.0": "1"
        }`)[1 .. $]);

    // Mixed version and non-version keys (versions first, then alphabetical).
    assert(toSortedPrettyJson(parseJSON(`{"linux": "1", "1.0.0": "2", "osx": "3"}`)) == outdent(`
        {
          "1.0.0": "2",
          "linux": "1",
          "osx": "3"
        }`)[1 .. $]);

    // Nested objects indent two spaces per level; inner keys are sorted too.
    assert(toSortedPrettyJson(parseJSON(`{"v": {"y": "1", "x": "2"}}`)) == outdent(`
        {
          "v": {
            "x": "2",
            "y": "1"
          }
        }`)[1 .. $]);

    // Arrays preserve element order.
    assert(toSortedPrettyJson(parseJSON(`[1, 2, 3]`)) == outdent(`
        [
          1,
          2,
          3
        ]`)[1 .. $]);
}
// editorconfig-checker-enable
