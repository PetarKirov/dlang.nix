module dlang_nix.utils.commands;

import std.algorithm : countUntil, filter, find, joiner, map, maxElement, sort, startsWith, endsWith, uniq;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.file : exists;
import std.format : format;
import std.json : parseJSON;
import std.process : executeShell, Config;
import std.range : empty, front;
import std.stdio : stderr;
import std.string : indexOf, outdent, splitLines, strip;
import std.typecons : Tuple, tuple;

import sparkles.versions.traits : hasSemVerComponents, supportsPrerelease;

alias Hash = string;
alias Url = string;

// ---------------------------------------------------------------------------
// Prefetch helpers (used by main.d).
// ---------------------------------------------------------------------------

Hash prefech(bool dryRun, Url url, bool unpack = false) {
    const output = executeCommand(
        dryRun,
        `nix-prefetch-url --print-path %s "%s"`
            .format(unpack ? "--unpack" : "", url)
    );
    if (output is null) return null;

    const lines = output.strip.splitLines;
    if (lines.length < 2) return null;

    const hash = lines[0].strip;
    const storePath = lines[1].strip;
    if (!storePath.startsWith("/nix/store/") || !storePath.exists) return null;

    const sri = executeCommand(
        dryRun,
        `nix-hash --to-sri --type sha256 "%s"`.format(hash)
    );
    return sri is null ? null : sri.strip;
}

/// Prefetches a URL and returns its base32 `sha256` — the exact format the
/// upstream `dub-to-nix` emits for dub-registry dependencies — or null on a
/// dry run / failure. Mirrors `nix-prefetch-url --type sha256 <url>`.
Hash prefetchUrlSha256(bool dryRun, Url url) {
    const output = executeCommand(
        dryRun,
        `nix-prefetch-url --type sha256 "%s"`.format(url)
    );
    if (output is null) return null;
    const lines = output.strip.splitLines;
    return lines.empty ? null : lines[$ - 1].strip;
}

/// Prefetches a git revision and returns its `sha256`, or null on a dry run /
/// failure. Mirrors `nix-prefetch-git <url> <rev>` and reads the `sha256`
/// field of its JSON output (used for git-based dub dependencies).
Hash prefetchGit(bool dryRun, string url, string rev) {
    const output = executeCommand(
        dryRun,
        `nix-prefetch-git "%s" "%s"`.format(url, rev)
    );
    if (output is null) return null;
    return parseJSON(output)["sha256"].str;
}

string executeCommand(bool dryRun, string command) {
    stderr.writefln(`> %s`, command);
    if (dryRun) return null;
    const result = executeShell(
        command,
        null,
        Config.stderrPassThrough,
    );
    return result.status == 0 ? result.output : null;
}

// ---------------------------------------------------------------------------
// Version predicates and selectors.
//
// Templated over any `sparkles:versions` scheme that exposes the SemVer
// triple. Callers use them via UFCS (`v.isStable`, `v.inMinorRange(lo, hi)`,
// `vers.latestPatchPerMinor`).
// ---------------------------------------------------------------------------

bool isStable(V)(V v) @safe pure nothrow @nogc
if (supportsPrerelease!V)
    => !v.isPrerelease;

/// Inclusive minor-version range filter. Patch and prerelease of `lo`/`hi`
/// are ignored — only (major, minor) are compared.
bool inMinorRange(V)(V v, V lo, V hi) @safe pure nothrow
if (hasSemVerComponents!V) {
    auto vKey = tuple(v.major, v.minor);
    auto loKey = tuple(lo.major, lo.minor);
    auto hiKey = tuple(hi.major, hi.minor);
    return vKey >= loKey && vKey <= hiKey;
}

/// Highest-patch version for each (major, minor). Output sorted descending.
V[] latestPatchPerMinor(V)(V[] vers) @safe pure
if (hasSemVerComponents!V) {
    auto sorted = vers.dup;
    sorted.sort!((a, b) => a > b);
    return sorted
        .uniq!((a, b) => a.major == b.major && a.minor == b.minor)
        .array;
}

unittest {
    import sparkles.versions : SemVer, Dmd;

    // ---- SemVer scheme (LDC-style tags) ----

    // isStable.
    assert(SemVer(1, 0, 0).isStable);
    assert(!SemVer(1, 0, 0, "beta1").isStable);

    // inMinorRange.
    auto lo = SemVer(2, 100, 0);
    auto hi = SemVer(2, 102, 0);
    assert(SemVer(2, 100, 0).inMinorRange(lo, hi));
    assert(SemVer(2, 100, 5).inMinorRange(lo, hi));   // patch ignored
    assert(SemVer(2, 101, 7).inMinorRange(lo, hi));
    assert(SemVer(2, 102, 99).inMinorRange(lo, hi));
    assert(!SemVer(2, 99, 99).inMinorRange(lo, hi));
    assert(!SemVer(2, 103, 0).inMinorRange(lo, hi));
    assert(!SemVer(3, 0, 0).inMinorRange(lo, hi));
    // Single-minor range (lo == hi).
    assert(SemVer(2, 100, 5).inMinorRange(SemVer(2, 100, 0), SemVer(2, 100, 0)));

    // latestPatchPerMinor collapses duplicates per (major, minor).
    auto vs = [
        SemVer(1, 0, 0), SemVer(1, 0, 5),
        SemVer(1, 1, 2), SemVer(1, 1, 0),
        SemVer(2, 0, 0),
    ];
    assert(latestPatchPerMinor(vs) ==
        [SemVer(2, 0, 0), SemVer(1, 1, 2), SemVer(1, 0, 5)]);
    auto vs2 = [SemVer(1, 0, 0, "rc.1"), SemVer(1, 0, 0)];
    assert(latestPatchPerMinor(vs2) == [SemVer(1, 0, 0)]);
    auto vs3 = [SemVer(1, 0, 0, "rc.2"), SemVer(1, 0, 0, "rc.10")];
    assert(latestPatchPerMinor(vs3) == [SemVer(1, 0, 0, "rc.10")]);

    // ---- Dmd scheme (zero-padded minor) ----

    assert(Dmd(2, 79, 0).isStable);
    assert(!Dmd(2, 79, 0, "rc.1").isStable);

    auto dlo = Dmd(2, 70, 0);
    auto dhi = Dmd(2, 100, 0);
    assert(Dmd(2, 79, 5).inMinorRange(dlo, dhi));
    assert(Dmd(2, 70, 0).inMinorRange(dlo, dhi));
    assert(Dmd(2, 100, 0).inMinorRange(dlo, dhi));
    assert(!Dmd(2, 69, 99).inMinorRange(dlo, dhi));
    assert(!Dmd(2, 101, 0).inMinorRange(dlo, dhi));

    auto dvs = [
        Dmd(2, 79, 0), Dmd(2, 79, 1),
        Dmd(2, 80, 0), Dmd(2, 80, 1),
    ];
    assert(latestPatchPerMinor(dvs) == [Dmd(2, 80, 1), Dmd(2, 79, 1)]);
}

// ---------------------------------------------------------------------------
// Tag fetcher.
//
// Uses `git ls-remote --tags <url>` — no auth required, works for any
// GitHub repo. Peeled refs (`^{}`) are kept during parsing: for annotated
// tags they carry the commit hash the tag points to (the direct ref only
// has the tag object's hash).
// ---------------------------------------------------------------------------

alias TagRev = Tuple!(string, "tag", string, "rev");

/// Fetches `(tag name, commit hash)` pairs from a GitHub `"owner/repo"`
/// via `git ls-remote`.
TagRev[] fetchTags(string repo) {
    const cmd = "git ls-remote --tags https://github.com/" ~ repo;
    stderr.writefln(`> %s`, cmd);
    const result = executeShell(cmd, null, Config.stderrPassThrough);
    enforce(result.status == 0, "git ls-remote failed: " ~ repo);
    return parseGitLsRemoteTags(result.output);
}

/// Resolves each requested version to the commit hash its `v<version>`
/// release tag points to (for fetchers that pin an explicit `rev`).
string[string] resolveTagRevs(string tagsRepo, const string[] versions) {
    const tagRevs = fetchTags(tagsRepo);
    string[string] revs;
    foreach (ver; versions) {
        const tag = "v" ~ ver;
        auto hit = tagRevs.find!(tr => tr.tag == tag);
        enforce(!hit.empty,
            "No tag " ~ tag ~ " found in repo " ~ tagsRepo);
        revs[ver] = hit.front.rev;
    }
    return revs;
}

/// Resolves an inclusive `[first, last]` minor range against the tags of
/// the given GitHub repo and returns the highest-patch stable release for
/// each minor, as version strings sorted ascending. An empty `last` means
/// "latest available stable tag".
///
/// Parameterised over a sparkles:versions scheme (e.g. `SemVer` for LDC's
/// canonical tags, `Dmd` for DMD's zero-padded minor convention). The
/// returned strings use the scheme's `toString`, so DMD comes back as
/// `"2.079.0"` and LDC as `"1.42.0"`.
string[] resolveVersionRange(Scheme)(string tagsRepo, string first, string last) {
    // `.value` on a parse-failed Expected throws — what we want for user
    // input.
    const lo = Scheme.parseLoose(first).value;

    auto stable = fetchTags(tagsRepo)
        .map!(tr => Scheme.parseLoose(tr.tag))
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

/// Pure: parses the output of `git ls-remote --tags <url>` into a list of
/// `(tag name, commit hash)` pairs in output order. A peeled ref
/// (`name^{}`) carries the commit an annotated tag points to, so it
/// overwrites the hash of its already-seen `name` entry; lightweight tags
/// only have the direct entry.
TagRev[] parseGitLsRemoteTags(string output) @safe pure {
    TagRev[] tagRevs;
    foreach (line; output.splitLines.map!(line => line.strip)) {
        const tabIdx = line.indexOf('\t');
        if (tabIdx < 0) continue;
        const hash = line[0 .. tabIdx];
        const refName = line[tabIdx + 1 .. $];
        if (!refName.startsWith("refs/tags/")) continue;
        auto name = refName["refs/tags/".length .. $];
        if (name.endsWith("^{}")) {
            name = name[0 .. $ - "^{}".length];
            const idx = tagRevs.countUntil!(tr => tr.tag == name);
            if (idx >= 0) tagRevs[idx].rev = hash;
        } else {
            tagRevs ~= TagRev(name, hash);
        }
    }
    return tagRevs;
}

// editorconfig-checker-disable
unittest {
    // Mixed peeled / non-peeled, junk lines, non-version tags. The peeled
    // `^{}` hash replaces the annotated tag object's hash; lightweight
    // tags (no peeled line) keep their direct hash.
    auto sample = outdent(`
        abc123	refs/tags/v1.0.0
        def456	refs/tags/v1.0.0^{}
        789ghi	refs/tags/v1.1.0
        000zzz	refs/tags/CI
        aaabbb	refs/heads/main
    `)[1 .. $];
    assert(parseGitLsRemoteTags(sample) == [
        TagRev("v1.0.0", "def456"),
        TagRev("v1.1.0", "789ghi"),
        TagRev("CI", "000zzz"),
    ]);
    assert(parseGitLsRemoteTags("") == []);
}
// editorconfig-checker-enable
