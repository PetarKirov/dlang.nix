#!/usr/bin/env -S rdmd -preview=shortenedMethods

import std.algorithm : joiner, map, predSwitch, sort, startsWith, uniq;
import std.array : array, join, split;
import std.conv : to;
import std.exception : enforce;
static import std.file;
import std.format : format;
import std.functional : adjoin;
import std.getopt : getopt, GetOptException, defaultGetoptFormatter;
static import std.getopt;
import std.json : JSONValue, JSONType, JSONOptions, parseJSON;
import std.parallelism : parallel;
import std.path : buildNormalizedPath, dirName;
import std.process : executeShell, Config;
import std.range : iota, walkLength;
import std.stdio : stdout, stderr;
import std.string : outdent, strip, toLower;
import std.typecons : tuple;

import dlang_nix.utils.commands : prefech, Version, Platform, Hash, Url;

enum Component { dmd, dmd_src, ldc, ldc_src };

alias UrlFormatter =
    Url function(Platform platform, Version compilerVersion) @safe pure;

alias PlatformQuery = Platform[] function(Version) @safe pure;

enum UnpackingNeeded : bool { no, yes }

struct ComponentInfo {
    UrlFormatter urlFormatter;
    PlatformQuery platforms;
    UnpackingNeeded unpackingNeed;
    string supportedVersionsFile;
}

@safe pure string suffix(Platform p) => p.startsWith("windows") ?
    "7z" : "tar.xz";

enum pkgsDir = __FILE_FULL_PATH__.dirName.buildNormalizedPath("..", "pkgs");

enum ComponentInfo[Component] supportedPlatforms = [
    Component.dmd: ComponentInfo(
        urlFormatter: (platform, compilerVersion) =>
            "http://downloads.dlang.org/releases/2.x/%s/dmd.%s.%s.%s"
                .format(compilerVersion, compilerVersion, platform, suffix(platform)),
        platforms: compVersion => [
            "linux", "osx", "freebsd-64", "windows"
        ],
        unpackingNeed: UnpackingNeeded.no,
        supportedVersionsFile: pkgsDir.buildNormalizedPath("dmd", "supported-binary-versions.json"),
    ),
    Component.dmd_src: ComponentInfo(
        urlFormatter: (platform, compilerVersion) =>
            "https://github.com/dlang/%s/archive/refs/tags/v%s.tar.gz"
                .format(platform, compilerVersion),
        platforms: compVersion => [
            ["dmd"],
            compVersion.split(".")[1].to!int >= 101 ? [] : ["druntime"],
            ["phobos", "tools"]
        ].join,
        unpackingNeed: UnpackingNeeded.yes,
        supportedVersionsFile: pkgsDir.buildNormalizedPath("dmd", "supported-source-versions.json"),
    ),
    Component.ldc: ComponentInfo(
        urlFormatter: (platform, compilerVersion) =>
            "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc2-%s-%s.%s"
                .format(compilerVersion, compilerVersion, platform, suffix(platform)),
        platforms: compVersion => [
            "android-aarch64", "android-armv7a",
            "freebsd-x86_64",
            "linux-aarch64", "linux-x86_64",
            "osx-arm64", "osx-x86_64",
            "windows-x64", "windows-x86"
        ],
        unpackingNeed: UnpackingNeeded.no,
        supportedVersionsFile: pkgsDir.buildNormalizedPath("ldc", "supported-binary-versions.json"),
    ),
    Component.ldc_src: ComponentInfo(
        urlFormatter: (platform, compilerVersion) =>
            "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc-%s-src.tar.gz"
                .format(compilerVersion, compilerVersion),
        platforms: compVersion => [
            "src"
        ],
        unpackingNeed: UnpackingNeeded.no,
        supportedVersionsFile: pkgsDir.buildNormalizedPath("ldc", "supported-source-versions.json"),
    ),
];

void main(string[] args) {
    Version[] componentVersions;
    Component component = Component.ldc;
    bool liveRun = false;

    auto parseCLI(string[] args) {
        std.getopt.arraySep = ",";
        return args.getopt(
            "versions", "list of component versions to fetch. For example, " ~
                    "2.099.1,2.100.2",
                &componentVersions,
            "component",
                // Ideally we would generate the list of allowed values as
                // opposed to this hardcoding
                "What component to fetch. dmd | dmd_src | ldc | ldc_src, " ~
                    "default ldc",
                &component,
            "dry-run",
                "Only print what would be done, but don't really act." ~
                    " Opposite of live-run. This is the default. ",
                (){liveRun = false;},
            "live-run",
                "Actually perform the fetching. Opposite of dry-run.",
                (){liveRun = true;}
        );
    }

    bool helpWanted = false;
    try {
        auto cli = parseCLI(args);
        helpWanted = cli.helpWanted;
    } catch (GetOptException) {
        helpWanted = true;
    }

    if (helpWanted) {
        auto w = stderr.lockingTextWriter();
        defaultGetoptFormatter(
            w,
            "fetch_binary.d - " ~
                "tool for fetching source and binary releases of DMD and LDC",
            parseCLI(args[0 .. 1]).options,
        );
        return;
    }

    componentVersions = componentVersions.length
        ? componentVersions
        : component == Component.ldc
        ? [ "1.34.0" ]
        : [ "2.105.0" ];

    const compilerInfo = supportedPlatforms[component];
    const platforms = componentVersions
        .map!(vers => compilerInfo.platforms(vers))
        .uniq
        .adjoin!(
            versArrays => enforce(versArrays.walkLength(2) == 1,
                "Requested versions differ in set of platforms they support. " ~
                "Please specify a set of versions with a common set of " ~
                "supported platforms."),
            versArrays => versArrays.front
        )[1];

    const getUrl = compilerInfo.urlFormatter;

    foreach (compilerVersion; componentVersions)
        stderr.writefln(
            "* Prefetching %s v%s for %s:",
            component,
            compilerVersion,
            platforms,
        );
    stderr.writeln("-----");

    auto jobs = componentVersions.map!(compilerVersion =>
        platforms.map!(platform =>
            tuple(compilerVersion, platform, getUrl(platform, compilerVersion),
                compilerInfo.unpackingNeed)
        ).array
    ).joiner.array;

    // Fetch in parallel into a pre-allocated array (thread-safe:
    // each index is written by exactly one worker).
    auto results = new Hash[](jobs.length);

    foreach (i; iota(jobs.length).parallel) {
        results[i] = prefech(!liveRun, jobs[i][2], jobs[i][3]);
    }

    // Build hashes AA from results (single-threaded).
    Hash[Platform][Version] hashes;
    foreach (i; 0 .. jobs.length) {
        hashes[jobs[i][0]][jobs[i][1]] = results[i];
    }

    if (!liveRun) {
        stderr.writeln("-----");
        stderr.writeln("Fetching was not performed, this was a dry run.");
    }

    if (liveRun) {
        const target = supportedPlatforms[component].supportedVersionsFile;
        const existingJson =
            std.file.exists(target) ? std.file.readText(target) : "";
        const merged = mergeHashesIntoJson(existingJson, hashes);
        const tmpFile = target ~ ".tmp";
        std.file.write(tmpFile, merged);
        std.file.rename(tmpFile, target);
        stderr.writefln("Updated %s", target);
    }

    stderr.writeln("-----");
    stderr.writeln("All done!\n");

    stdout.writeln(
        toSortedPrettyJson(hashes.JSONValue)
    );
}

/// Parses `existingJson` (if non-empty), merges `newHashes` into it, and
/// returns the result rendered as pretty JSON with a trailing newline.
/// New entries overwrite existing version/platform pairs.
string mergeHashesIntoJson(string existingJson, Hash[Platform][Version] newHashes) {
    Hash[Platform][Version] allHashes;
    if (existingJson.length > 0) {
        auto existing = parseJSON(existingJson);
        foreach (string ver, platforms; existing.object) {
            foreach (string platform, hashVal; platforms.object) {
                allHashes[ver][platform] =
                    hashVal.type == JSONType.null_ ? cast(Hash) null : hashVal.str;
            }
        }
    }
    foreach (ver, platforms; newHashes) {
        foreach (platform, hash; platforms) {
            allHashes[ver][platform] = hash;
        }
    }
    return toSortedPrettyJson(allHashes.JSONValue) ~ "\n";
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
}
// editorconfig-checker-enable

/// Renders a JSONValue as pretty-printed JSON with keys sorted alphabetically.
/// Does not escape forward slashes in string values.
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
            return `"` ~ val.str ~ `"`;
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
            auto keys = obj.keys.sort.release;
            if (keys.length == 0) return "{}";
            auto inner = indent ~ "  ";
            auto items = keys.map!(k =>
                format(`%s"%s": %s`, inner, k, toSortedPrettyJson(obj[k], inner))
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

    // Empty containers render inline.
    assert(toSortedPrettyJson(parseJSON(`{}`)) == "{}");
    assert(toSortedPrettyJson(parseJSON(`[]`)) == "[]");

    // Object keys are emitted in sorted order.
    assert(toSortedPrettyJson(parseJSON(`{"b": "1", "a": "2"}`)) == outdent(`
        {
          "a": "2",
          "b": "1"
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
