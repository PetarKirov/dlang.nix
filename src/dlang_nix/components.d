module dlang_nix.components;

import std.array : split, join;
import std.algorithm : startsWith;
import std.conv : to;
import std.format : format;
import std.path : buildNormalizedPath, dirName;

import dlang_nix.utils.commands : Hash, Url;

@safe pure:

alias Version = string;
alias Platform = string;

enum Component { dmd, dmd_src, ldc, ldc_src };

alias UrlFormatter = Url function(Platform platform, Version compilerVersion);

alias PlatformQuery = Platform[] function(Version);

enum UnpackingNeeded : bool { no, yes }

struct ComponentInfo {
    UrlFormatter urlFormatter;
    PlatformQuery platforms;
    UnpackingNeeded unpackingNeed;
    string supportedVersionsFile;
}

string suffix(Platform p) => p.startsWith("windows") ? "7z" : "tar.xz";

enum pkgsDir = __FILE_FULL_PATH__.dirName.buildNormalizedPath("..", "..", "pkgs");

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
