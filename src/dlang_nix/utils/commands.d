module dlang_nix.utils.commands;

import std.algorithm : filter, map, sort, startsWith, endsWith, uniq;
import std.array : array;
import std.exception : enforce;
import std.file : exists;
import std.format : format;
import std.process : executeShell, Config;
import std.stdio : stderr;
import std.string : indexOf, outdent, splitLines, strip;
import std.typecons : tuple;

import sparkles.semver : SemVer, SemVerParseMode;

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
// SemVer predicates and selectors.
//
// Free functions over sparkles.semver.SemVer so callers use them via UFCS
// (`v.isStable`, `v.inMinorRange(lo, hi)`, `vers.latestPatchPerMinor`).
// No wrapper struct: callers parse with `SemVer.parse(s, SemVerParseMode.loose)`
// and handle the returned `Expected!SemVer` directly.
// ---------------------------------------------------------------------------

bool isStable(SemVer v) @safe pure nothrow @nogc =>
    v.prerelease.length == 0;

/// Inclusive minor-version range filter. Patch and prerelease of `lo`/`hi`
/// are ignored — only (major, minor) are compared.
bool inMinorRange(SemVer v, SemVer lo, SemVer hi) @safe pure nothrow {
    auto vKey = tuple(v.major, v.minor);
    auto loKey = tuple(lo.major, lo.minor);
    auto hiKey = tuple(hi.major, hi.minor);
    return vKey >= loKey && vKey <= hiKey;
}

/// Highest-patch version for each (major, minor). Output sorted descending.
SemVer[] latestPatchPerMinor(SemVer[] vers) @safe pure {
    auto sorted = vers.dup;
    sorted.sort!((a, b) => a > b);
    return sorted
        .uniq!((a, b) => a.major == b.major && a.minor == b.minor)
        .array;
}

unittest {
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
    // Same minor collapses to whichever has highest patch (stable beats
    // prerelease at equal patch).
    auto vs2 = [SemVer(1, 0, 0, "rc.1"), SemVer(1, 0, 0)];
    assert(latestPatchPerMinor(vs2) == [SemVer(1, 0, 0)]);
    auto vs3 = [SemVer(1, 0, 0, "rc.2"), SemVer(1, 0, 0, "rc.10")];
    assert(latestPatchPerMinor(vs3) == [SemVer(1, 0, 0, "rc.10")]);
}

// ---------------------------------------------------------------------------
// Tag fetcher.
//
// Uses `git ls-remote --tags --refs <url>` — no auth required, works for
// any GitHub repo. `--refs` filters out peeled refs (`^{}`); we strip them
// defensively too.
// ---------------------------------------------------------------------------

/// Fetches tag names from a GitHub `"owner/repo"` via `git ls-remote`.
string[] fetchTags(string repo) {
    const cmd = "git ls-remote --tags --refs https://github.com/" ~ repo;
    stderr.writefln(`> %s`, cmd);
    const result = executeShell(cmd, null, Config.stderrPassThrough);
    enforce(result.status == 0, "git ls-remote failed: " ~ repo);
    return parseGitLsRemoteTags(result.output);
}

/// Pure: parses the output of `git ls-remote --tags [--refs] <url>` into
/// a list of tag names (with peeled refs removed).
string[] parseGitLsRemoteTags(string output) @safe pure {
    return output.splitLines
        .map!(line => line.strip)
        .filter!(line => line.length > 0)
        .map!((line) {
            const tabIdx = line.indexOf('\t');
            return tabIdx < 0 ? "" : line[tabIdx + 1 .. $];
        })
        .filter!(refName => refName.startsWith("refs/tags/"))
        .map!(refName => refName["refs/tags/".length .. $])
        .filter!(name => !name.endsWith("^{}"))
        .array;
}

// editorconfig-checker-disable
unittest {
    // Mixed peeled / non-peeled, junk lines, non-version tags.
    auto sample = outdent(`
        abc123	refs/tags/v1.0.0
        def456	refs/tags/v1.0.0^{}
        789ghi	refs/tags/v1.1.0
        000zzz	refs/tags/CI
        aaabbb	refs/heads/main
    `)[1 .. $];
    assert(parseGitLsRemoteTags(sample) == ["v1.0.0", "v1.1.0", "CI"]);
    assert(parseGitLsRemoteTags("") == []);
}
// editorconfig-checker-enable
