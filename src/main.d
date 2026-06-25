import std.algorithm : joiner, map, uniq;
import std.array : array, join;
import std.conv : to;
import std.exception : enforce;
static import std.file;
import std.functional : adjoin;
import std.getopt : getopt, GetOptException, defaultGetoptFormatter;
static import std.getopt;
import std.parallelism : parallel;
import std.range : iota, walkLength;
import std.stdio : stdout, stderr;
import std.typecons : tuple;

import dlang_nix.utils.commands : prefech, Hash, resolveVersionRange, resolveTagRevs;
import dlang_nix.utils.json : hashesToJsonValue, mergeHashesIntoJson, toSortedPrettyJson;
import dlang_nix.components : Platform, Families, familyPinsRev;

/// `name1 | name2 | …` over every family — the allowed `--component` tokens.
string componentNames() {
    string[] names;
    static foreach (F; Families)
        names ~= F.name;
    return names.join(" | ");
}

/// Prefetches the requested versions of family `F` and writes/prints the
/// `version -> platform -> hash` table. The version pipeline is typed on
/// `F.VersionType`; `string` appears only at the CLI and JSON boundaries.
void runFetch(F)(string[] versionStrs, string firstVersion, string lastVersion, bool liveRun) {
    alias V = F.VersionType;

    V[] versions;
    if (firstVersion.length > 0 || lastVersion.length > 0) {
        enforce(firstVersion.length > 0,
            "--last-version requires --first-version.");
        enforce(versionStrs.length == 0,
            "--versions is mutually exclusive with " ~
                "--first-version/--last-version.");

        stderr.writefln(
            "Resolving %s..%s (repo: %s)...",
            firstVersion,
            lastVersion.length > 0 ? lastVersion : "latest",
            F.tagsRepo);

        versions = resolveVersionRange!V(F.tagsRepo, firstVersion, lastVersion);
        enforce(versions.length > 0,
            "No stable releases found in range " ~
                firstVersion ~ ".." ~
                (lastVersion.length > 0 ? lastVersion : "latest"));
        stderr.writefln("Resolved to %s versions: %-(%s, %)",
            versions.length, versions);
    }
    else
        versions = versionStrs.length
            ? versionStrs.map!(s => V.parseLoose(s).value).array
            : F.defaultVersions;

    // Pin the commit each release tag points to, for families whose nix
    // fetcher takes an explicit `rev` (optional capability).
    Hash[string] revs;
    static if (familyPinsRev!F)
        revs = resolveTagRevs!V(F.tagsRepo, versions);

    const platforms = versions
        .map!(v => F.platforms(v))
        .uniq
        .adjoin!(
            versArrays => enforce(versArrays.walkLength(2) == 1,
                "Requested versions differ in set of platforms they support. " ~
                "Please specify a set of versions with a common set of " ~
                "supported platforms."),
            versArrays => versArrays.front
        )[1];

    foreach (v; versions)
        stderr.writefln(
            "* Prefetching %s v%s for %s:",
            F.name,
            v,
            platforms,
        );
    stderr.writeln("-----");

    auto jobs = versions.map!(v =>
        platforms.map!(platform =>
            tuple(v, platform, F.url(platform, v), F.unpackingNeed)
        ).array
    ).joiner.array;

    // Fetch in parallel into a pre-allocated array (thread-safe:
    // each index is written by exactly one worker).
    auto results = new Hash[](jobs.length);

    foreach (i; iota(jobs.length).parallel) {
        results[i] = prefech(!liveRun, jobs[i][2], jobs[i][3]);
    }

    // Build hashes AA from results (single-threaded). Keyed by the version's
    // canonical string at the serialization boundary.
    Hash[Platform][string] hashes;
    foreach (i; 0 .. jobs.length) {
        hashes[jobs[i][0].to!string][jobs[i][1]] = results[i];
    }
    foreach (ver, rev; revs) {
        hashes[ver]["rev"] = rev;
    }

    if (!liveRun) {
        stderr.writeln("-----");
        stderr.writeln("Fetching was not performed, this was a dry run.");
    }

    if (liveRun) {
        const target = F.supportedVersionsFile;
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

void main(string[] args) {
    string[] componentVersions;
    string component = "ldc-binary";
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
                "What component to fetch. " ~ componentNames() ~
                    ", default ldc-binary",
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

    // Dispatch the runtime `--component` token to its compile-time family.
    static foreach (F; Families)
        if (component == F.name) {
            runFetch!F(componentVersions, firstVersion, lastVersion, liveRun);
            return;
        }
    enforce(false,
        "unknown --component '" ~ component ~ "'; expected one of: " ~ componentNames());
}
