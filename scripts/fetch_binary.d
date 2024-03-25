#!/usr/bin/env -S rdmd -preview=shortenedMethods

import std.algorithm : joiner, map, predSwitch, startsWith, uniq;
import std.array : array, join, split;
import std.conv : to;
import std.exception : enforce;
import std.format : format;
import std.functional : adjoin;
import std.getopt : getopt, GetOptException, defaultGetoptFormatter;
static import std.getopt;
import std.json : JSONValue, JSONOptions;
import std.parallelism : parallel;
import std.process : executeShell, Config;
import std.range : walkLength;
import std.stdio : stdout, stderr;
import std.string : strip, toLower;
import std.typecons : tuple;

import utils : prefech, Version, Platform, Hash, Url;

enum Compiler { dmd, dmd_src, ldc, ldc_src };

alias UrlFormatter =
    Url function(Platform platform, Version compilerVersion) @safe pure;

alias PlatformQuery = Platform[] function(Version) @safe pure;

enum UnpackingNeeded : bool { no, yes }

struct CompilerInfo {
    UrlFormatter urlFormatter;
    PlatformQuery platforms;
    UnpackingNeeded unpackingNeed;
}

@safe pure string suffix(Platform p) => p.startsWith("windows") ?
    "7z" : "tar.xz";

enum CompilerInfo[Compiler] supportedPlatforms = [
    Compiler.dmd: CompilerInfo(
        (platform, compilerVersion) =>
            "http://downloads.dlang.org/releases/2.x/%s/dmd.%s.%s.%s"
                .format(compilerVersion, compilerVersion, platform, suffix(platform)),
        compVersion => [
            "linux", "osx", "freebsd-64", "windows"
        ],
        UnpackingNeeded.no,
    ),
    Compiler.dmd_src: CompilerInfo(
        (platform, compilerVersion) =>
            "https://github.com/dlang/%s/archive/refs/tags/v%s.tar.gz"
                .format(platform, compilerVersion),
        compVersion => [
            ["dmd"],
            compVersion.split(".")[1].to!int >= 101 ? [] : ["druntime"],
            ["phobos", "tools"]
        ].join,
        UnpackingNeeded.yes,
    ),
    Compiler.ldc: CompilerInfo(
        (platform, compilerVersion) =>
            "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc2-%s-%s.%s"
                .format(compilerVersion, compilerVersion, platform, suffix(platform)),
        compVersion => [
            "android-aarch64", "android-armv7a",
            "freebsd-x86_64",
            "linux-aarch64", "linux-x86_64",
            "osx-arm64", "osx-x86_64",
            "windows-x64", "windows-x86"
        ],
        UnpackingNeeded.no,
    ),
    Compiler.ldc_src: CompilerInfo(
        (platform, compilerVersion) =>
            "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc-%s-src.tar.gz"
                .format(compilerVersion, compilerVersion),
        compVersion => [
            "src"
        ],
        UnpackingNeeded.no,
    ),
];

void main(string[] args) {
    Version[] compilerVersions;
    Compiler compiler = Compiler.ldc;
    bool liveRun = false;

    auto parseCLI(string[] args) {
        std.getopt.arraySep = ",";
        return args.getopt(
            "versions", "list of compiler versions to fetch. For example, " ~
                    "2.099.1,2.100.2",
                &compilerVersions,
            "compiler",
                // Ideally we would generate the list of allowed values as
                // opposed to this hardcoding
                "What compiler to fetch. dmd | dmd_src | ldc | ldc_src, " ~
                    "default ldc",
                &compiler,
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

    compilerVersions = compilerVersions.length
        ? compilerVersions
        : compiler == Compiler.ldc
        ? [ "1.34.0" ]
        : [ "2.105.0" ];

    const compilerInfo = supportedPlatforms[compiler];
    const platforms = compilerVersions.map!(vers =>
        compilerInfo.platforms(vers)
    ).uniq.adjoin!(
        versArrays => enforce(versArrays.walkLength(2) == 1,
            "Requested versions differ in set of platforms they support. " ~
                "Please specify a set of versions with a common set of " ~
                "supported platforms."),
        versArrays => versArrays.front
    )[1];

    const getUrl = compilerInfo.urlFormatter;

    foreach (compilerVersion; compilerVersions)
        stderr.writefln(
            "* Prefetching %s v%s for %s:",
            compiler,
            compilerVersion,
            platforms,
        );
    stderr.writeln("-----");

    Hash[Platform][Version] hashes;

    auto jobs = compilerVersions.map!(compilerVersion =>
        platforms.map!(platform =>
            tuple(compilerVersion, platform, getUrl(platform, compilerVersion),
                compilerInfo.unpackingNeed)
        ).array
    ).joiner.array;

    foreach (job; jobs.parallel) {
        const compilerVersion = job[0], platform = job[1], url = job[2],
            unpack = job[3];
        hashes[compilerVersion][platform] = prefech(!liveRun, url, unpack);
    }

    if (!liveRun) {
        stderr.writeln("-----");
        stderr.writeln("Fetching was not performed, this was a dry run.");
    }
    stderr.writeln("-----");
    stderr.writeln("All done!\n");

    stdout.writeln(
        hashes.JSONValue.toPrettyString(JSONOptions.doNotEscapeSlashes)
    );
}
