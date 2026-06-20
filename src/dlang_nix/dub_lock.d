module dlang_nix.dub_lock;

import std.algorithm : startsWith;
import std.exception : enforce;
import std.file : exists, readText, rmdirRecurse;
import std.format : format;
import std.json : JSONValue, JSONType, parseJSON;
import std.path : buildPath;
import std.process : executeShell, Config;
import std.stdio : stderr;
import std.string : strip;

import dlang_nix.utils.commands : Hash, prefetchUrlSha256, prefetchGit;

/// A dependency-hash resolver. Injected into `dubLockFromSelections` so the
/// pure lock builder can be unit-tested without shelling out.
struct HashResolver {
    /// Resolves a dub-registry dependency `(name, version)` to its sha256.
    Hash delegate(string pname, string ver) registry;
    /// Resolves a git dependency `(url, rev)` to its sha256.
    Hash delegate(string url, string rev) git;
}

/// Re-implements the relevant part of nixpkgs' `dub-to-nix`: turns a parsed
/// `dub.selections.json` into the `{ "dependencies": { ... } }` lock object
/// consumed by `buildDubPackage`'s `dubLock`. Registry deps become
/// `{version, sha256}`; git deps (whose `repository` is `git+<url>`) become
/// `{version, repository, sha256}`. Path selections are skipped and branch
/// (`~master`) versions are rejected — matching dub-to-nix.
JSONValue dubLockFromSelections(JSONValue selections, HashResolver resolve) {
    JSONValue[string] deps;
    foreach (string pname, depVal; selections["versions"].object) {
        // Expand a bare version string into `{ "version": <v> }`.
        JSONValue dep = depVal.type == JSONType.object
            ? depVal : JSONValue(["version": depVal.str]);

        if ("path" in dep)
            continue; // local path selection: nothing to fetch

        const ver = dep["version"].str;
        enforce(!ver.startsWith("~"),
            format("dependency %s pins a branch version %s; pin a concrete " ~
                "release instead (patch dub.selections.json if needed)", pname, ver));

        if (auto repoP = "repository" in dep) {
            const repository = (*repoP).str;
            enforce(repository.startsWith("git+"),
                format("dependency %s has a non-git repository %s", pname, repository));
            const url = repository["git+".length .. $];
            deps[pname] = JSONValue([
                "version": JSONValue(ver),
                "repository": JSONValue(url),
                "sha256": JSONValue(resolve.git(url, ver)),
            ]);
        } else {
            deps[pname] = JSONValue([
                "version": JSONValue(ver),
                "sha256": JSONValue(resolve.registry(pname, ver)),
            ]);
        }
    }
    return JSONValue(["dependencies": JSONValue(deps)]);
}

// editorconfig-checker-disable
unittest {
    auto sel = parseJSON(`{
        "fileVersion": 1,
        "versions": {
            "libdparse": "0.25.1",
            "expanded": { "version": "1.2.3" },
            "local": { "path": "../local" },
            "fromgit": { "version": "abc123", "repository": "git+https://example.com/x.git" }
        }
    }`);
    auto lock = dubLockFromSelections(sel, HashResolver(
        (string p, string v) => "sha-" ~ p ~ "-" ~ v,
        (string u, string r) => "git-" ~ r,
    ));
    auto deps = lock["dependencies"];

    assert(deps["libdparse"]["version"].str == "0.25.1");
    assert(deps["libdparse"]["sha256"].str == "sha-libdparse-0.25.1");
    // Bare-string and expanded-object selections are handled the same way.
    assert(deps["expanded"]["sha256"].str == "sha-expanded-1.2.3");
    // Path selections are dropped entirely.
    assert(("local" in deps.object) is null);
    // Git deps strip the `git+` prefix and carry the repository url.
    assert(deps["fromgit"]["repository"].str == "https://example.com/x.git");
    assert(deps["fromgit"]["sha256"].str == "git-abc123");
}

unittest {
    import std.exception : assertThrown;

    // Branch (`~master`) versions are rejected.
    auto sel = parseJSON(`{"versions": {"x": "~master"}}`);
    assertThrown(dubLockFromSelections(sel, HashResolver((p, v) => "", (u, r) => "")));
}
// editorconfig-checker-enable

/// Best-effort recursive delete of a temp directory; swallows errors.
private void removeQuietly(string dir) nothrow {
    try
        rmdirRecurse(dir);
    catch (Exception) {
    }
}

/// Generates the dub lock for a single tagged release of `repo`
/// (`"owner/name"`). Clones the tag, runs `dub upgrade` when it ships no
/// `dub.selections.json` (dfix does not), then resolves every dependency's
/// hash via `nix-prefetch-url` / `nix-prefetch-git`. Returns
/// `JSONValue(null)` on a dry run.
JSONValue generateDubLock(string repo, string ver, bool dryRun) {
    if (dryRun) {
        stderr.writefln(
            "> (dry-run) would clone v%s of %s and resolve its dub dependencies",
            ver, repo);
        return JSONValue(null);
    }

    const work = executeShell("mktemp -d").output.strip;
    enforce(work.length > 0, "mktemp -d failed");
    scope (exit)
        removeQuietly(work);

    const srcDir = work.buildPath("src");
    const cloneCmd = format(
        `git clone --quiet --depth 1 --branch "v%s" "https://github.com/%s" "%s"`,
        ver, repo, srcDir);
    stderr.writefln("> %s", cloneCmd);
    enforce(executeShell(cloneCmd, null, Config.stderrPassThrough).status == 0,
        format("git clone of %s v%s failed", repo, ver));

    const selectionsFile = srcDir.buildPath("dub.selections.json");
    if (!selectionsFile.exists) {
        stderr.writefln("  %s v%s ships no dub.selections.json -> dub upgrade", repo, ver);
        const r = executeShell("dub upgrade", null, Config.stderrPassThrough, size_t.max, srcDir);
        enforce(r.status == 0, format("dub upgrade failed for %s v%s", repo, ver));
    }
    enforce(selectionsFile.exists,
        format("no dub.selections.json for %s v%s after dub upgrade", repo, ver));

    return dubLockFromSelections(parseJSON(selectionsFile.readText), HashResolver(
        (string pname, string v) => prefetchUrlSha256(false,
            format("https://code.dlang.org/packages/%s/%s.zip", pname, v)),
        (string url, string rev) => prefetchGit(false, url, rev),
    ));
}
