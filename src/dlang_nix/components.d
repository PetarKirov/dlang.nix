module dlang_nix.components;

import std.array : split, join;
import std.algorithm : startsWith;
import std.conv : to;
import std.format : format;
import std.path : buildNormalizedPath, dirName;

import sparkles.versions : SemVer, Dmd;

import dlang_nix.utils.commands : Hash, Url, resolveTagRevs, resolveVersionRange;

alias Version = string;
alias Platform = string;

/// Resolves a `[first, last]` minor range into an explicit version list,
/// emitting each version in the component's native tag form. DMD uses a
/// zero-padded 3-digit minor (`2.070.0`); LDC follows canonical SemVer.
/// Impure (`@system`) since it shells out for tag discovery, hence declared
/// outside the module's `@safe pure:` region.
alias VersionRangeResolver =
    Version[] function(string tagsRepo, string first, string last);

/// Resolves each requested version to the commit hash its release tag
/// points to (for fetchers that pin an explicit `rev`). Impure
/// (`@system`) since it shells out to `git ls-remote`.
alias RevResolver =
    Hash[Version] function(string tagsRepo, const Version[] versions);

@safe pure:

enum Component { dmd, dmd_src, ldc, ldc_src, dub, dcd, dfix, dscanner };

alias UrlFormatter = Url function(Platform platform, Version compilerVersion);

alias PlatformQuery = Platform[] function(Version);

enum UnpackingNeeded : bool { no, yes }

struct ComponentInfo {
    UrlFormatter urlFormatter;
    PlatformQuery platforms;
    UnpackingNeeded unpackingNeed;
    string supportedVersionsFile;
    string tagsRepo;   // "owner/repo" on GitHub for tag discovery
    Version[] defaultVersions;  // fetched when no versions are requested
    VersionRangeResolver resolveVersions;
    RevResolver resolveRevs;  // set when the nix fetcher pins an explicit rev
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
        tagsRepo: "dlang/dmd",
        defaultVersions: [ "2.105.0" ],
        resolveVersions: &resolveVersionRange!Dmd,
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
        tagsRepo: "dlang/dmd",
        defaultVersions: [ "2.105.0" ],
        resolveVersions: &resolveVersionRange!Dmd,
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
        tagsRepo: "ldc-developers/ldc",
        defaultVersions: [ "1.35.0" ],
        resolveVersions: &resolveVersionRange!SemVer,
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
        tagsRepo: "ldc-developers/ldc",
        defaultVersions: [ "1.35.0" ],
        resolveVersions: &resolveVersionRange!SemVer,
    ),
    Component.dub: ComponentInfo(
        urlFormatter: (platform, compilerVersion) =>
            "https://github.com/dlang/%s/archive/refs/tags/v%s.tar.gz"
                .format(platform, compilerVersion),
        platforms: compVersion => [
            "dub"
        ],
        unpackingNeed: UnpackingNeeded.yes,
        supportedVersionsFile: pkgsDir.buildNormalizedPath("dub", "supported-source-versions.json"),
        tagsRepo: "dlang/dub",
        defaultVersions: [ "1.41.0" ],
        resolveVersions: &resolveVersionRange!SemVer,
        resolveRevs: &resolveTagRevs,
    ),
    // dlang-community developer tools, built from their GitHub source archives
    // with nixpkgs' `buildDubPackage`. Like `dub`, each pins the commit its
    // release tag points to (`rev`) alongside the unpacked source hash (`src`).
    // The per-version dub dependency lock (`dub-lock.json`) is produced
    // separately by `scripts/update-dub-locks.sh` via nixpkgs' `dub-to-nix`.
    Component.dcd: ComponentInfo(
        urlFormatter: (platform, compilerVersion) =>
            "https://github.com/dlang-community/DCD/archive/refs/tags/v%s.tar.gz"
                .format(compilerVersion),
        platforms: compVersion => [
            "src"
        ],
        unpackingNeed: UnpackingNeeded.yes,
        supportedVersionsFile: pkgsDir.buildNormalizedPath("dcd", "supported-source-versions.json"),
        tagsRepo: "dlang-community/DCD",
        defaultVersions: [ "0.16.2" ],
        resolveVersions: &resolveVersionRange!SemVer,
        resolveRevs: &resolveTagRevs,
    ),
    Component.dfix: ComponentInfo(
        urlFormatter: (platform, compilerVersion) =>
            "https://github.com/dlang-community/dfix/archive/refs/tags/v%s.tar.gz"
                .format(compilerVersion),
        platforms: compVersion => [
            "src"
        ],
        unpackingNeed: UnpackingNeeded.yes,
        supportedVersionsFile: pkgsDir.buildNormalizedPath("dfix", "supported-source-versions.json"),
        tagsRepo: "dlang-community/dfix",
        defaultVersions: [ "0.3.5" ],
        resolveVersions: &resolveVersionRange!SemVer,
        resolveRevs: &resolveTagRevs,
    ),
    Component.dscanner: ComponentInfo(
        urlFormatter: (platform, compilerVersion) =>
            "https://github.com/dlang-community/D-Scanner/archive/refs/tags/v%s.tar.gz"
                .format(compilerVersion),
        platforms: compVersion => [
            "src"
        ],
        unpackingNeed: UnpackingNeeded.yes,
        supportedVersionsFile: pkgsDir.buildNormalizedPath("dscanner", "supported-source-versions.json"),
        tagsRepo: "dlang-community/D-Scanner",
        defaultVersions: [ "0.15.2" ],
        resolveVersions: &resolveVersionRange!SemVer,
        resolveRevs: &resolveTagRevs,
    ),
];
