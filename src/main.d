import std.algorithm : filter, joiner, map, maxElement, predSwitch, sort, startsWith, uniq;
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
import std.range : iota, walkLength;
import std.stdio : stdout, stderr;
import std.string : outdent, strip;
import std.typecons : tuple;

import sparkles.versions : SemVer, Dmd;

import dlang_nix.utils.commands :
    prefech, Hash, Url,
    fetchTags, inMinorRange, isStable, latestPatchPerMinor;
import dlang_nix.components : Platform, Version, Component, supportedPlatforms, ComponentInfo;

void main(string[] args) {
    Version[] componentVersions;
    Component component = Component.ldc;
    bool liveRun = false;
    string firstVersion, lastVersion;

    auto parseCLI(string[] args) {
        std.getopt.arraySep = ",";
        return args.getopt(
            "versions", "Explicit list of component versions to fetch. " ~
                    "For example, 2.099.1,2.100.2. Mutually exclusive with " ~
                    "--first-version/--last-version.",
                &componentVersions,
            "first-version",
                "First minor (inclusive) of an auto-resolved version range, " ~
                    "e.g. 2.100.",
                &firstVersion,
            "last-version",
                "Last minor (inclusive) of an auto-resolved version range, " ~
                    "e.g. 2.108. Optional; defaults to the latest stable " ~
                    "tag available in the repo.",
                &lastVersion,
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

    const compilerInfo = supportedPlatforms[component];

    // Resolve --first-version/--last-version into an explicit version list.
    if (firstVersion.length > 0 || lastVersion.length > 0) {
        enforce(firstVersion.length > 0,
            "--last-version requires --first-version.");
        enforce(componentVersions.length == 0,
            "--versions is mutually exclusive with " ~
                "--first-version/--last-version.");

        stderr.writefln(
            "Resolving %s..%s (repo: %s)...",
            firstVersion,
            lastVersion.length > 0 ? lastVersion : "latest",
            compilerInfo.tagsRepo);

        // DMD uses a zero-padded 3-digit minor (`2.070.0`); LDC follows
        // canonical SemVer. Pick the matching scheme so `toString` re-emits
        // each tag in its native form.
        componentVersions =
            (component == Component.dmd || component == Component.dmd_src)
                ? resolveVersionRange!Dmd(
                    compilerInfo.tagsRepo, firstVersion, lastVersion)
                : resolveVersionRange!SemVer(
                    compilerInfo.tagsRepo, firstVersion, lastVersion);
        enforce(componentVersions.length > 0,
            "No stable releases found in range " ~
                firstVersion ~ ".." ~
                (lastVersion.length > 0 ? lastVersion : "latest"));
        stderr.writefln("Resolved to %s versions: %-(%s, %)",
            componentVersions.length, componentVersions);
    }
    else
    {
        componentVersions = componentVersions.length
            ? componentVersions
            : component == Component.ldc
            ? [ "1.35.0" ]
            : [ "2.105.0" ];
    }

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
        toSortedPrettyJson(hashesToJsonValue(hashes))
    );
}

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

/// Resolves an inclusive `[first, last]` minor range against the tags of
/// the given GitHub repo and returns the highest-patch stable release for
/// each minor, as `Version` strings sorted ascending. An empty `last`
/// means "latest available stable tag".
///
/// Parameterised over a sparkles:versions scheme (e.g. `SemVer` for LDC's
/// canonical tags, `Dmd` for DMD's zero-padded minor convention). The
/// returned strings use the scheme's `toString`, so DMD comes back as
/// `"2.079.0"` and LDC as `"1.42.0"`.
Version[] resolveVersionRange(Scheme)(string tagsRepo, string first, string last) {
    // `.value` on a parse-failed Expected throws — what we want for user
    // input.
    const lo = Scheme.parseLoose(first).value;

    auto stable = fetchTags(tagsRepo)
        .map!(s => Scheme.parseLoose(s))
        .joiner
        .filter!isStable
        .array;
    enforce(stable.length > 0, "No stable tags found in repo " ~ tagsRepo);

    const hi = last.length > 0
        ? Scheme.parseLoose(last).value
        : stable.maxElement;
    enforce(lo <= hi,
        "--first-version " ~ first ~ " must not be greater than " ~
            (last.length > 0 ? "--last-version " ~ last : "latest tag " ~ hi.to!string));

    auto vers = stable
        .filter!(v => v.inMinorRange(lo, hi))
        .array
        .latestPatchPerMinor;

    vers.sort!((a, b) => a < b);  // ascending for user display
    return vers.map!(v => v.to!string).array;
}
