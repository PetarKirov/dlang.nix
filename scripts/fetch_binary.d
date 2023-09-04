#!/usr/bin/env -S rdmd -preview=shortenedMethods

import std.algorithm : map, startsWith;
import std.format : format;
import std.stdio : writeln, writefln;
import std.getopt : getopt, defaultGetoptPrinter;
import std.parallelism : parallel;
import std.string : strip;
import std.typecons : tuple;

enum Compiler { dmd, ldc };
alias Version = string;
alias Platform = string;
alias Hash = string;
alias Url = string;

alias UrlFormatter = Url function(Platform platform, Version compilerVersion);

struct CompilerInfo { UrlFormatter urlFormatter; Platform[] platforms; }

string suffix(Platform p) => p.startsWith("windows") ? "7z" : "tar.xz";

enum CompilerInfo[Compiler] supportedPlatforms = [
    Compiler.dmd: CompilerInfo(
        (platform, compilerVersion) => "http://downloads.dlang.org/releases/2.x/%s/dmd.%s.%s.%s"
            .format(compilerVersion, compilerVersion, platform, suffix(platform)),
        [
            "linux", "osx", "freebsd-64", "windows"
        ],
    ),
    Compiler.ldc: CompilerInfo(
        (platform, compilerVersion) => "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc2-%s-%s.%s"
            .format(compilerVersion, compilerVersion, platform, suffix(platform)),
        [
            "android-aarch64", "android-armv7a",
            "freebsd-x86_64",
            "linux-aarch64", "linux-x86_64",
            "osx-arm64", "osx-x86_64",
            "windows-x64", "windows-x86"
        ],
    ),
];

void main(string[] args) {
    Version compilerVersion;
    Compiler compiler = Compiler.ldc;
    bool dryRun = true;

    auto help = args.getopt(
        "version", &compilerVersion,
        "compiler", &compiler,
        "dry-run", &dryRun,
    );

    compilerVersion = compilerVersion
        ? compilerVersion
        : compiler == Compiler.ldc
        ? "1.34.0"
        : "2.105.0";

    if (help.helpWanted)
        defaultGetoptPrinter("Some information about the program.", help.options);

    const compilerInfo = supportedPlatforms[compiler];
    const platforms = compilerInfo.platforms;
    const getUrl = compilerInfo.urlFormatter;

    writefln("Prefetching %s v%s for %s:", compiler, compilerVersion, platforms);
    writeln("-----");

    Hash[Platform] hashes;

    foreach (platform; platforms.parallel) {
        const url = getUrl(platform, compilerVersion);
        if (const hash = prefech(dryRun, url))
            hashes[platform] = hash;
    }

    writeln("-----");
    writeln("All done!\n");

    foreach (platform, hash; platforms.map!(p => tuple(p, p in hashes)))
       `"%s" = "%s";`.writefln(
            platform,
            hash ? *hash : "<not available>"
        );
}

Hash prefech(bool dryRun, Url url) =>
    executeCommand(
        dryRun,
        `nix store prefetch-file --json "%s" | jq -r '.hash'`.format(url)
    ).strip;

string executeCommand(bool dryRun, string command) {
    `> %s`.writefln(command);
    import std.process : executeShell;
    if (dryRun) return null;
    const result = executeShell(command);
    return result.status == 0 ? result.output : null;
}
