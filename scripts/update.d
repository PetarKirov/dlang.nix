import std;
import std.file : isFile;

import sparkles.versions : SemVer;

import dlang_nix.utils.commands :
    fetchTags, isStable, latestPatchPerMinor;

enum defaultPackagesDir = __FILE_FULL_PATH__.dirName.buildNormalizedPath("..", "pkgs");

alias PackageName = string;
alias Hash = string;
alias Version = string;
struct Ref { string name, repo; }
struct Resolution { Ref input; Hash hash; }
alias Result = Hash[PackageName][Version];

JSONValue toJson(T)(T value)
{
    static if (isSomeString!T || isScalarType!T)
        return JSONValue(value);
    else static if (isArray!T)
        return JSONValue(value.map!(v => toJson(v)).array);
    else static if (isAssociativeArray!T)
        return value.byPair
            .map!(pair => tuple(pair[0], pair[1].toJson))
            .array
            .assocArray
            .JSONValue;
    else static if (is(T == struct))
    {
        JSONValue[string] res;
        static foreach (idx, field; T.tupleof)
            res[field.stringof] = value.tupleof[idx].toJson;
        return JSONValue(res);
    }
    else
        static assert(0, "Unsupport type: " ~ T.stringof);
}

struct PackageInfo
{
    string name;
    Ref[] inputs;
    size_t primaryInputIdx;
    ref const(Ref) primaryInput() const { return inputs[primaryInputIdx]; }
}

alias PackageInputResolutions = Resolution[string];

void main()
{
    auto r = allPackages()
        .map!getPackageInfo
        .map!getResolutions
        .array;

    toJson(r).toPrettyString(JSONOptions.doNotEscapeSlashes).writeln;
}

string[] allPackages(string pkgsDir = defaultPackagesDir)
{
    return pkgsDir
        .dirEntries(SpanMode.shallow, false)
        .map!(x => x.name.buildNormalizedPath("flake.nix"))
        .array;
}

PackageInfo getPackageInfo(string flakePath)
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
    return PackageInfo(
        flakePath.dirName.baseName,
        inputs,
        primaryIdx
    );
}

Result getResolutions(PackageInfo info, ushort maxCount = 100, bool includePrereleases = false)
{
    return info.primaryInput.repo
        .getTags(maxCount, includePrereleases)
        .map!((tag) {
            auto resolutions = info.inputs
                .map!(input => tuple(input.name, "sha256"))
                //.map!(input => prefetchAndResolveInput(input, tag))
                .assocArray;
            return tuple(tag, resolutions);
        })
        .assocArray;
}

/// Returns up to `maxCount` of the most recent latest-patch-per-minor tags
/// from a `github:<owner>/<repo>` flake input. Composes the helpers in
/// dlang_nix.utils.commands.
string[] getTags(string repoUrl, ushort maxCount, bool includePrereleases = false)
{
    auto parts = repoUrl.findSplit(":");
    enforce(parts, "Expected format: github:<owner>/<repo>, got: " ~ repoUrl);
    enforce(parts[0] == "github", "Unsupported protocol: " ~ parts[0]);

    auto vers = fetchTags(parts[2])
        .map!(s => SemVer.parseLoose(s))
        .joiner
        .filter!(v => includePrereleases || v.isStable)
        .array;

    return vers.latestPatchPerMinor
        .take(maxCount)
        .map!(v => v.to!string)
        .array;
}

Resolution prefetchAndResolveInput(Ref input, string gitTag)
{
    const flakeUrl = input.repo ~ "/" ~ gitTag;
    writefln("Prefeching '%s'...", flakeUrl);
    const res = ["nix", "flake", "prefetch", "--json", flakeUrl].execute;
    enforce(res.status == 0, "nix prefetch failed " ~ flakeUrl);
    return Resolution(
        input,
        res.output.parseJSON()["hash"].str
    );
}
