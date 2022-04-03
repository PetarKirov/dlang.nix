#!/usr/bin/env dub
/+ dub.sdl:
    name "update-nix-inputs"
    dependency "semver" version="~>0.3.4"
+/

import std;
import semver : SemVer;
import std.file : isFile;

enum defaultPackagesDir = __FILE_FULL_PATH__.dirName.buildNormalizedPath("..", "pkgs");

struct Ref { string name, repo; }

struct PackageInputs
{
    Ref[] inputs;
    size_t primaryInputIdx;
    ref const(Ref) primaryInput() const { return inputs[primaryInputIdx]; }
}

alias Sha256 = ubyte[32];
struct Resolution { Input i; Sha256 hash; }

alias PackageInputResolutions = Resolution[string];

void main()
{
    allPackages()
        .map!getPackageInputs
        // .map!getTags
        .writefln!"%(%s\n%)";
        // .writefln!"%(%-(%s, %)\n%)";
}

string[] allPackages(string pkgsDir = defaultPackagesDir)
{
    return pkgsDir
        .dirEntries(SpanMode.shallow, false)
        .map!(x => x.name.buildNormalizedPath("flake.nix"))
        .array;
}

PackageInputs getPackageInputs(string flakePath)
in (flakePath.isFile)
{
    import std.process : execute;

    const res = ["nix", "eval", "--json", "-f", flakePath, "inputs"].execute;
    enforce(res.status == 0, "nix eval failed");

    const j = parseJSON(res.output);
    const primaryInput = j["primary"]["follows"].str;
    size_t primaryIdx = -1;
    size_t idx;

    auto inputs = j.object.byPair
        .filter!(pair => pair[0] != "primary")
        .tee!((pair) {
            if (pair[0] == primaryInput)
                primaryIdx = idx;
            idx++;
        })
        .map!(pair => Ref(pair[0], pair[1]["url"].str))
        .array;

    enforce(
        primaryIdx != -1 && inputs[primaryIdx].name == primaryInput,
        "primary input not found"
    );
    return PackageInputs(
        inputs,
        primaryIdx
    );
}

unittest
{
    assert(getNixFlakeInputs("pkgs/dmd").primaryInput == "dmd");
}

string[] getTags(string repoUri, bool includePrereleases = false)
{
    auto parts = repoUri.findSplit(":");
    enforce(parts, "Expected format: <protocol>:<repo>, got: " ~ repoUri);

    auto protocol = parts[0];
    auto repo = parts[2];

    SemVer[] versions;

    switch(protocol)
    {
        default: throw new Error("Unknown protocol: " ~ protocol);
        case "github": {
            versions = getGitHubRepoTags(repo);
        }
    }

    return versions.map!(v => repoUri ~ "@" ~ v.toString()).array;
}

SemVer[] getGitHubRepoTags(string repo, bool includePrereleases = false)
{
    import std.net.curl : get;
    auto url = "https://api.github.com/repos/" ~ repo ~ "/tags";
    return url.get
        .parseJSON
        .array
        .map!(j => j.object["name"].str.SemVer)
        .filter!(ver => includePrereleases || ver.isStable)
        .array;
}
