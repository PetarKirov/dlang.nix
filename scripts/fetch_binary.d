#!/usr/bin/env -S rdmd -preview=shortenedMethods

import std.algorithm : map, startsWith, joiner;
import std.array : array;
import std.format : format;
import std.getopt : getopt, GetOptException, defaultGetoptFormatter;
static import std.getopt;
import std.json : JSONValue, JSONOptions;
import std.parallelism : parallel;
import std.process : executeShell, Config;
import std.stdio : stdout, stderr;
import std.string : strip;
import std.typecons : tuple;

import utils : prefech, Version, Platform, Hash, Url;

enum Compiler { dmd, ldc, ldc_src };

alias UrlFormatter = Url function(Platform platform, Version compilerVersion);

struct CompilerInfo { UrlFormatter urlFormatter; Platform[] platforms; }

string suffix(Platform p) => p.startsWith("windows") ? "7z" : "tar.xz";

enum CompilerInfo[Compiler] supportedPlatforms = [
    Compiler.dmd: CompilerInfo(
        (platform, compilerVersion) =>
            "http://downloads.dlang.org/releases/2.x/%s/dmd.%s.%s.%s"
                .format(compilerVersion, compilerVersion, platform, suffix(platform)),
            [
                "linux", "osx", "freebsd-64", "windows"
            ],
    ),
    Compiler.ldc: CompilerInfo(
        (platform, compilerVersion) =>
            "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc2-%s-%s.%s"
                .format(compilerVersion, compilerVersion, platform, suffix(platform)),
            [
                "android-aarch64", "android-armv7a",
                "freebsd-x86_64",
                "linux-aarch64", "linux-x86_64",
                "osx-arm64", "osx-x86_64",
                "windows-x64", "windows-x86"
            ],
    ),
    Compiler.ldc_src: CompilerInfo(
        (platform, compilerVersion) =>
            "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc-%s-src.tar.gz"
                .format(compilerVersion, compilerVersion),
            [
                "src"
            ],
    ),
];

void main(string[] args) {
    Version[] compilerVersions;
    Compiler compiler = Compiler.ldc;
    bool dryRun = true;

    auto parseCLI(string[] args) {
        std.getopt.arraySep = ",";
        return args.getopt(
            "versions", &compilerVersions,
            "compiler", &compiler,
            "dry-run", &dryRun,
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
                "tool for fetching binary releases of DMD and LDC",
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
    const platforms = compilerInfo.platforms;
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
            tuple(compilerVersion, platform, getUrl(platform, compilerVersion))
        ).array
    ).joiner.array;

    foreach (job; jobs.parallel) {
        const compilerVersion = job[0], platform = job[1], url = job[2];
        hashes[compilerVersion][platform] = prefech(dryRun, url);
    }

    if (dryRun) {
        stderr.writeln("-----");
        stderr.writeln("Fetching was not performed, this was a dry run.");
    }
    stderr.writeln("-----");
    stderr.writeln("All done!\n");

    stdout.writeln(
        hashes.JSONValue.toPrettyString(JSONOptions.doNotEscapeSlashes)
    );
}
