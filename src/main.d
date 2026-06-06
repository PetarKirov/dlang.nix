import std.algorithm : filter, joiner, map, maxElement, sort, startsWith, uniq;
import std.array : array, split;
import std.conv : to;
import std.exception : enforce;
static import std.file;
import std.format : format;
import std.functional : adjoin;
import std.getopt : getopt, GetOptException, defaultGetoptFormatter;
static import std.getopt;
import std.parallelism : parallel;
import std.path : buildNormalizedPath, dirName;
import std.range : iota, walkLength;
import std.stdio : stdout, stderr;
import std.string : strip;
import std.typecons : tuple;

import sparkles.versions : SemVer, Dmd;

import dlang_nix.utils.commands :
    prefech, Hash, Url,
    fetchTags, inMinorRange, isStable, latestPatchPerMinor;
import dlang_nix.utils.json : hashesToJsonValue, mergeHashesIntoJson, toSortedPrettyJson;
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
            "dlang-nix-fetcher - " ~
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
