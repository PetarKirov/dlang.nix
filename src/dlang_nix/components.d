module dlang_nix.components;

import std.algorithm : findSplitBefore, startsWith;
import std.array : array, join, replace, split;
import std.ascii : isDigit;
import std.conv : to;
import std.format : format;
import std.meta : AliasSeq, allSatisfy;
import std.path : buildNormalizedPath, dirName;
import std.string : representation;
import std.typecons : Nullable;

import sparkles.versions : SemVer;
import sparkles.versions : DmdVer = Dmd;
import sparkles.versions.traits : isVersionScheme;

import dlang_nix.utils.commands : Hash, Url;

/// A download platform token as the upstream URL scheme spells it
/// (`"linux"`, `"osx-x86_64"`, or a source-archive repo name like `"phobos"`).
/// Distinct from a Nix system double (`dlang_nix.ci.weights.NixSystem`).
alias Platform = string;

/// Whether an archive must be unpacked after fetching.
enum UnpackingNeeded : bool { no, yes }

// ---------------------------------------------------------------------------
// The PackageFamily concept
//
// A package family is a plain struct conforming to `isPackageFamily!C`, in the
// spirit of `sparkles:versions` (a scheme is "a struct + a static assert, no
// base class, no registration"). It carries its attr-prefix `name`, the
// `VersionType` its tags follow, and the static fetch surface that used to live
// in the `ComponentInfo` function-pointer table.
// ---------------------------------------------------------------------------

/// Exercises the required surface so a failed `isPackageFamily` can be
/// diagnosed by instantiating `checkPackageFamily!C` directly.
void checkPackageFamily(C)() {
    string n = C.name;
    assert(n.length);
    static assert(isVersionScheme!(C.VersionType));
    alias V = C.VersionType;
    Url u = C.url(Platform.init, V.init);
    Platform[] ps = C.platforms(V.init);
    UnpackingNeeded un = C.unpackingNeed;
    string f = C.supportedVersionsFile;
    string r = C.tagsRepo;
    V[] dv = C.defaultVersions;
}

/// True for a struct that models a package family.
enum isPackageFamily(C) = is(typeof(checkPackageFamily!C));

/// Optional capability: a family that pins the commit each release tag points
/// to (only `Dub`). Detected like the `sparkles:versions` optional traits.
template familyPinsRev(C) {
    static if (__traits(hasMember, C, "pinsRev"))
        enum familyPinsRev = C.pinsRev;
    else
        enum familyPinsRev = false;
}

@safe:

string suffix(Platform p) => p.startsWith("windows") ? "7z" : "tar.xz";

enum pkgsDir = __FILE_FULL_PATH__.dirName.buildNormalizedPath("..", "..", "pkgs");

// ---------------------------------------------------------------------------
// The five families. Source builds take no suffix; the binary variant is
// suffixed `-binary`. The `name` is the attr/pname prefix (and CI weight key).
// ---------------------------------------------------------------------------

/// DMD binary releases from downloads.dlang.org.
struct DmdBinary {
    enum string name = "dmd-binary";
    alias VersionType = DmdVer;

    static Url url(Platform platform, VersionType v) {
        const vs = v.to!string;
        return "http://downloads.dlang.org/releases/2.x/%s/dmd.%s.%s.%s"
            .format(vs, vs, platform, suffix(platform));
    }

    static Platform[] platforms(VersionType) => ["linux", "osx", "freebsd-64", "windows"];

    enum UnpackingNeeded unpackingNeed = UnpackingNeeded.no;
    enum string supportedVersionsFile =
        pkgsDir.buildNormalizedPath("dmd", "supported-binary-versions.json");
    enum string tagsRepo = "dlang/dmd";

    static VersionType[] defaultVersions() => [VersionType(2, 105, 0)];

    static assert(isPackageFamily!DmdBinary);
}

/// DMD built from source (dmd/druntime/phobos/tools GitHub archives).
struct Dmd {
    enum string name = "dmd";
    alias VersionType = DmdVer;

    static Url url(Platform platform, VersionType v) =>
        "https://github.com/dlang/%s/archive/refs/tags/v%s.tar.gz"
            .format(platform, v.to!string);

    // druntime merged into dmd at 2.101, so it is a separate archive only
    // before then.
    static Platform[] platforms(VersionType v) => [
        ["dmd"],
        v.minor >= 101 ? cast(string[])[] : ["druntime"],
        ["phobos", "tools"],
    ].join;

    enum UnpackingNeeded unpackingNeed = UnpackingNeeded.yes;
    enum string supportedVersionsFile =
        pkgsDir.buildNormalizedPath("dmd", "supported-source-versions.json");
    enum string tagsRepo = "dlang/dmd";

    static VersionType[] defaultVersions() => [VersionType(2, 105, 0)];

    static assert(isPackageFamily!Dmd);
}

/// LDC binary releases from GitHub.
struct LdcBinary {
    enum string name = "ldc-binary";
    alias VersionType = SemVer;

    static Url url(Platform platform, VersionType v) {
        const vs = v.to!string;
        return "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc2-%s-%s.%s"
            .format(vs, vs, platform, suffix(platform));
    }

    static Platform[] platforms(VersionType) => [
        "android-aarch64", "android-armv7a",
        "freebsd-x86_64",
        "linux-aarch64", "linux-x86_64",
        "osx-arm64", "osx-x86_64",
        "windows-x64", "windows-x86",
    ];

    enum UnpackingNeeded unpackingNeed = UnpackingNeeded.no;
    enum string supportedVersionsFile =
        pkgsDir.buildNormalizedPath("ldc", "supported-binary-versions.json");
    enum string tagsRepo = "ldc-developers/ldc";

    static VersionType[] defaultVersions() => [VersionType(1, 35, 0)];

    static assert(isPackageFamily!LdcBinary);
}

/// LDC built from the release source tarball.
struct Ldc {
    enum string name = "ldc";
    alias VersionType = SemVer;

    static Url url(Platform, VersionType v) {
        const vs = v.to!string;
        return "https://github.com/ldc-developers/ldc/releases/download/v%s/ldc-%s-src.tar.gz"
            .format(vs, vs);
    }

    static Platform[] platforms(VersionType) => ["src"];

    enum UnpackingNeeded unpackingNeed = UnpackingNeeded.no;
    enum string supportedVersionsFile =
        pkgsDir.buildNormalizedPath("ldc", "supported-source-versions.json");
    enum string tagsRepo = "ldc-developers/ldc";

    static VersionType[] defaultVersions() => [VersionType(1, 35, 0)];

    static assert(isPackageFamily!Ldc);
}

/// dub built from its GitHub source archive. Pins an explicit `rev`.
struct Dub {
    enum string name = "dub";
    alias VersionType = SemVer;

    static Url url(Platform platform, VersionType v) =>
        "https://github.com/dlang/%s/archive/refs/tags/v%s.tar.gz"
            .format(platform, v.to!string);

    static Platform[] platforms(VersionType) => ["dub"];

    enum UnpackingNeeded unpackingNeed = UnpackingNeeded.yes;
    enum string supportedVersionsFile =
        pkgsDir.buildNormalizedPath("dub", "supported-source-versions.json");
    enum string tagsRepo = "dlang/dub";

    static VersionType[] defaultVersions() => [VersionType(1, 41, 0)];

    /// Optional capability: the nix fetcher pins the tag's commit.
    enum bool pinsRev = true;

    static assert(isPackageFamily!Dub);
}

/// The single registry: CLI tokens, dispatch, and allowed-value help are all
/// inferred from this list via `F.name`.
alias Families = AliasSeq!(DmdBinary, Dmd, LdcBinary, Ldc, Dub);
static assert(allSatisfy!(isPackageFamily, Families));

// ---------------------------------------------------------------------------
// baseFamily — the family matcher
// ---------------------------------------------------------------------------

/// A package "family" is the attr name with its trailing `-<version>` removed.
/// Versions are sanitised to digits/underscores, so the version always starts
/// at the first `-` immediately followed by a digit. Names without such a
/// marker (the unversioned aliases like `ldc-bootstrap`) are returned as-is.
string baseFamily(string pkg) pure nothrow {
    // Split before the first `-<digit>`. The needle `"-0"` matches positionally:
    // its `-` must match a literal `-`, while the `0` placeholder stands for any
    // digit. With no such marker, `findSplitBefore` yields the whole name in [0].
    // Operate on the byte `representation` so `find` doesn't auto-decode UTF
    // (which would throw and break `nothrow`).
    const fam = pkg.representation
        .findSplitBefore!((h, n) => n == '-' ? h == '-' : h.isDigit)("-0".representation);
    return cast(string) fam[0];
}

@("dlang_nix.components.baseFamily")
unittest {
    assert(baseFamily("dmd-2_112_0") == "dmd");
    assert(baseFamily("dmd-binary-2_098_0") == "dmd-binary");
    assert(baseFamily("ldc-binary-1_42_0-beta2") == "ldc-binary");
    assert(baseFamily("dub-1_43_0-alpha-5efed36") == "dub");
    assert(baseFamily("ldc-bootstrap") == "ldc-bootstrap");
    assert(baseFamily("dub") == "dub");
}

// ---------------------------------------------------------------------------
// PackageRelease — a family at a concrete version
// ---------------------------------------------------------------------------

/// A package family resolved to a version: `family + version`. The verbatim
/// `rawVersion` (underscore form, as it appears in the Nix attr) backs an exact
/// `toString` round-trip; `ver` is the best-effort typed parse used for
/// ordering, empty for unversioned aliases or an unparseable version.
struct PackageRelease(C) if (isPackageFamily!C) {
    alias Family = C;

    string rawVersion; // "2_098_0", or "" when the attr is bare (`dmd`)
    Nullable!(C.VersionType) ver;

    /// Splits an attr (`baseFamily(attr) == C.name` required) into the verbatim
    /// version remainder and a best-effort typed parse.
    static PackageRelease parse(string attr) {
        PackageRelease r;
        if (attr.length > C.name.length) {
            assert(attr[0 .. C.name.length] == C.name && attr[C.name.length] == '-',
                "attr '" ~ attr ~ "' is not in family '" ~ C.name ~ "'");
            r.rawVersion = attr[C.name.length + 1 .. $];
            auto p = C.VersionType.parse(r.rawVersion.replace("_", "."));
            if (p.hasValue)
                r.ver = p.value;
        } else
            assert(attr == C.name, "attr '" ~ attr ~ "' is not family '" ~ C.name ~ "'");
        return r;
    }

    /// Reconstructs the Nix attr name exactly.
    string toString() const => rawVersion.length ? C.name ~ "-" ~ rawVersion : C.name;

    /// Total order by version (a versionless release sorts first), tie-broken
    /// by the raw string so distinct attrs never compare equal.
    int opCmp(in PackageRelease o) const {
        import std.algorithm.comparison : cmp;

        if (ver.isNull != o.ver.isNull)
            return ver.isNull ? -1 : 1;
        if (!ver.isNull)
            if (const c = ver.get.opCmp(o.ver.get))
                return c;
        return cmp(rawVersion, o.rawVersion);
    }

    bool opEquals(in PackageRelease o) const => rawVersion == o.rawVersion;

    size_t toHash() const @trusted pure nothrow {
        import core.internal.hash : hashOf;

        return hashOf(rawVersion);
    }
}

@("dlang_nix.components.PackageRelease")
unittest {
    // Round-trips exactly, and parses the typed version under the family scheme.
    auto d = PackageRelease!DmdBinary.parse("dmd-binary-2_098_0");
    assert(d.toString == "dmd-binary-2_098_0");
    assert(!d.ver.isNull && d.ver.get == DmdVer(2, 98, 0));

    auto l = PackageRelease!Ldc.parse("ldc-1_42_0");
    assert(l.toString == "ldc-1_42_0");
    assert(!l.ver.isNull && l.ver.get == SemVer(1, 42, 0));

    // A prerelease with a hyphenated identifier round-trips.
    auto b = PackageRelease!LdcBinary.parse("ldc-binary-1_42_0-beta2");
    assert(b.toString == "ldc-binary-1_42_0-beta2");
    assert(!b.ver.isNull);

    // Bare alias: no version, still round-trips.
    auto bare = PackageRelease!Dmd.parse("dmd");
    assert(bare.toString == "dmd");
    assert(bare.ver.isNull);

    // Ordering by version, with raw-string tie-break and versionless-first.
    auto lo = PackageRelease!Ldc.parse("ldc-1_40_0");
    auto hi = PackageRelease!Ldc.parse("ldc-1_42_0");
    assert(lo < hi);
    assert(PackageRelease!Ldc.parse("ldc") < lo); // versionless sorts first
}
