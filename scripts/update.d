#!/usr/bin/env dub
/+ dub.sdl:
    name "update-nix-inputs"
    dependency "semver" version="~>0.3.4"
    dflags "-preview=shortenedMethods"
+/

import std;
import semver : SemVer, VersionPart;
import std.file : isFile;

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

unittest
{
    assert(getPackageInfo("pkgs/dmd/flake.nix").primaryInput.name == "dmd");
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

string[] getTags(string repoUrl, ushort maxCount, bool includePrereleases = false)
{
    auto parts = repoUrl.findSplit(":");
    enforce(parts, "Expected format: <protocol>:<repo>, got: " ~ repoUrl);

    auto protocol = parts[0];
    auto repo = parts[2];

    string[] tags;
    switch(protocol)
    {
        default: throw new Error("Unknown protocol: " ~ protocol);
        case "github":
        {
            tags = getGitHubRepoTags(repo, includePrereleases);
            break;
        }
    }

    return zip(tags, tags.map!(tag => SemVer(tag)).array)
        .sort!((a, b) => a[1] > b[1])
        .uniq!((a, b) => equalMajorAndMinorVersion(a[1], b[1]))
        .take(maxCount)
        .map!"a[0]"
        .array;
}

string[] getGitHubRepoTags(string repo, bool includePrereleases = false)
{
    string getGHPage(int page)
    {
        return "https://api.github.com/repos/%s/tags?per_page=100&page=%s"
            .format(repo, page);
    }

    return fetchPagedResponse!(JSONValue)(
        getGHPage(1),
        [ "Authorization": "Bearer " ~ environment["GH_TOKEN"]],
        (const(char)[] rawResponse) => rawResponse.parseJSON.array,
        (response, headers) => getNextPageFromLinkHeader(headers),
    )
        .map!(j => j.object["name"].str)
        .filter!(ver => SemVer(ver).isValid)
        .filter!(ver => includePrereleases || SemVer(ver).isStable)
        .array;
}

string getNextPageFromLinkHeader(string[string] headers)
{
    auto linkHeader = headers.tryGet("Link", "link");
    if (!linkHeader)
        return null;
    return parseLinkHeader(*linkHeader)
        .firstOrDefault!(l => l.rel == "next")
        .url;
}

alias Link = Tuple!(string, "url", string, "rel");

Link[] parseLinkHeader(string header)
{
    return header
        .split(",")
        .map!(x => x.split(";").map!(part => part.strip).array)
        .map!(parts => Link(
            parts[0][1 .. $ - 1], // "<URL>"" -> "URL"
            parts[1 .. $]
                .find!((string p) => p.startsWith("rel"))
                .map!(p => p[5 .. $ - 1]) // `rel="value"` -> `"value"`
                .firstOrDefault!"!!a"
        ))
        .array;
}

auto firstOrDefault
    (alias predicate, Range)
    (Range r, ElementType!Range default_ = ElementType!Range.init)
{
    auto res = r.find!predicate;
    return res.empty ? default_ : res.front;
}

V* tryGet(K, V)(V[K] aa, K[] keys...) => keys
    .map!(k => k in aa)
    .firstOrDefault!"!!a";

alias Deserialize(T) = T[] function(const(char)[] response);
alias NextPage(T) = string function(
    T[] data,
    string[string] httpResponseHeaders,
);

T[] fetchPagedResponse(T)(
    string firstPage,
    string[string] requestHeaders,
    Deserialize!T deserialize,
    NextPage!T getNextPage,
)
{
    import std.net.curl : get, HTTP;

    T[] result;
    int page = 0;
    bool moreData = false;
    auto nextPage = firstPage;

    auto client = HTTP();

    foreach (key, value; requestHeaders)
        client.addRequestHeader(key, value);

    do
    {
        auto response = deserialize(get(nextPage, client));
        result ~= response;
        nextPage = getNextPage(response, client.responseHeaders);
    }
    while (nextPage);

    return result;
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

bool equalMajorAndMinorVersion(SemVer a, SemVer b) =>
    a == b || a.differAt(b) >= VersionPart.PATCH;

unittest
{
    assert(equalMajorAndMinorVersion(SemVer("1.2.3"), SemVer("1.2.3")));
    assert(equalMajorAndMinorVersion(SemVer("1.2.3"), SemVer("1.2.4")));
    assert(equalMajorAndMinorVersion(SemVer("1.2.0"), SemVer("1.2.3")));
    assert(equalMajorAndMinorVersion(SemVer("1.2.3-rc.1"), SemVer("1.2.3-rc.1")));
    assert(equalMajorAndMinorVersion(SemVer("1.2.3-rc.1"), SemVer("1.2.3-rc.2")));

    assert(!equalMajorAndMinorVersion(SemVer("1.2.3"), SemVer("1.3.3")));
    assert(!equalMajorAndMinorVersion(SemVer("1.2.3"), SemVer("1.0.3")));
    assert(!equalMajorAndMinorVersion(SemVer("1.2.3"), SemVer("2.2.3")));
    assert(!equalMajorAndMinorVersion(SemVer("1.2.3"), SemVer("0.2.3")));
}
