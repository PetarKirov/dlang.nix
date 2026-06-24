import std.algorithm : joiner, map, uniq;
import std.array : array;
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

import dlang_nix.utils.commands : prefech, Hash;
import dlang_nix.utils.json : hashesToJsonValue, mergeHashesIntoJson, toSortedPrettyJson;
import dlang_nix.components : Platform, Version, Component, supportedPlatforms, ComponentInfo;
import dlang_nix.ci.cli : runCi;

void main(string[] args) {
    // `ci` subcommand: CI build-matrix helpers (see dlang_nix.ci.cli). Anything
    // else falls through to the default release-prefetcher below.
    if (args.length >= 2 && args[1] == "ci") {
        runCi(args[1 .. $]);
        return;
    }

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
                "What component to fetch. dmd | dmd_src | ldc | ldc_src | dub, " ~
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
                "tool for fetching source and binary releases of DMD, LDC and dub",
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

        componentVersions = compilerInfo.resolveVersions(
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
            : compilerInfo.defaultVersions.dup;
    }

    // Pin the commit each release tag points to, for components whose nix
    // fetcher takes an explicit `rev` alongside the hash.
    Hash[Version] revs;
    if (compilerInfo.resolveRevs !is null)
        revs = compilerInfo.resolveRevs(
            compilerInfo.tagsRepo, componentVersions);

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
    foreach (compilerVersion, rev; revs) {
        hashes[compilerVersion]["rev"] = rev;
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
