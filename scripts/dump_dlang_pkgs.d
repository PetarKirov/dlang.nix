#!/usr/bin/env -S rdmd -gc
module scripts.dump_dlang_pkgs;

import std.net.curl : get;
import std.json;
import std.path : dirName, absolutePath;
import std.file : write, mkdirRecurse, readText;
import std.algorithm : map, filter, each, startsWith, any;
import std.stdio : writeln;
import std.process : executeShell;
import std.string : strip;
import std.array : array, join;
import std.traits : isNumeric, EnumMembers, hasUDA, getUDAs;
import std.parallelism : parallel;
import std.conv : to;

struct Version
{
    string ver;
    string rev;
    string hash;
}

struct Source
{
    string url;
    string type;
}

struct Package
{
    string name;
    Source src;
    Version[string] versions;
}

string enumToString(T)(in T value) if (is(T == enum))
{

    switch (value)
    {
        static foreach (enumMember; EnumMembers!T)
        {
    case enumMember:
            {
                static if (!hasUDA!(enumMember, StringRepresentation))
                {
                    return enumMember.to!string;
                }
                else
                {
                    return getUDAs!(enumMember, StringRepresentation)[0].repr;
                }
            }
        }
    default:
        assert(0, "Not supported case: " ~ value.to!string);
    }
}

JSONValue toJSON(T)(in T value)
{
    static if (is(T == enum))
    {
        return JSONValue(value.enumToString);
    }
    else static if (is(T == bool) || is(T == string) || isNumeric!T)
        return JSONValue(value);
    else static if (is(T == U[string], U))
    {
        JSONValue[string] result;
        foreach (k, v; value)
            result[k] = v.toJSON;
        return JSONValue(result);
    }
    else static if (is(T == U[], U))
    {
        JSONValue[] result;
        foreach (elem; value)
            result ~= elem.toJSON;
        return JSONValue(result);
    }
    else static if (is(T == struct))
    {
        JSONValue[string] result;
        static foreach (idx, field; T.tupleof)
            result[__traits(identifier, field)] = value.tupleof[idx].toJSON;
        return JSONValue(result);
    }
    else
        static assert(false, "Unsupported type: `" ~ T ~ "`");
}

Source getRepo(JSONValue repo)
{
    string baseUrl = "";
    switch (repo["kind"].str)
    {
    case "github":
        baseUrl = "https://github.com";
        break;
    case "gitlab":
        baseUrl = "https://gitlab.com";
        break;
    case "bitbucket":
        baseUrl = "https://bitbucket.org";
        break;
    default:
        writeln("Unknown kind: ", repo["kind"].str);
        assert(0);
    }

    return Source(
        baseUrl ~ "/" ~ repo["owner"].str ~ "/" ~ repo["project"].str,
        repo["kind"].str
    );
}

Version[string] getVersions(string name, JSONValue versions, string url)
{
    Version[string] ret;
    foreach (x; versions.array)
    {
        auto v = Version(
            x["version"].str,
            x["commitID"].str,
            getHash(name, x, url));
        synchronized
        {
            ret[x["version"].str] = v;
        }
    }
    return ret;
}

string getHash(string name, JSONValue v, string url)
{
    if (dubPkgs.keys.any!(x => x == name) && dubPkgs[name].versions.keys.any!(
            x => x == v["version"].str))
    {
        return dubPkgs[name].versions[v["version"].str].hash;
    }
    writeln("getting hash for ", name, " ", v["version"].str, " ", v["commitID"].str);
    return executeShell(
        "nix hash to-sri sha256:$(nix-prefetch-git --url "
            ~ url ~ " --quiet --rev " ~ v["commitID"].str ~ " | jq -r '.sha256')"
    ).output.strip;
}

string dubPkgsPath = dirName(__FILE_FULL_PATH__) ~ "/../pkgs/build-dub-package/dubPkgs.json";
immutable Package[string] dubPkgs;
shared static this()
{
    auto dubPkgsJson = parseJSON(readText(dubPkgsPath));
    Package[string] dubPkgsTemp;
    dubPkgsJson.object
        .each!((JSONValue pkg) {
            Version[string] vers;
            pkg["versions"].object
                .each!((v) {
                    vers[v["ver"].str] = Version(v["ver"].str, v["rev"].str, v["hash"].str);
                });
            dubPkgsTemp[pkg["name"].str] = Package(pkg["name"].str, Source(pkg["src"]["type"].str, pkg["src"]["url"]
                .str), vers);
        });
    dubPkgs = cast(immutable) dubPkgsTemp;
}

void main(string[] args)
{
    string packagesPath = dirName(__FILE__.absolutePath) ~ "/../pkgs/build-dub-package/packages.json";
    // Request url

    auto dump = get("https://code.dlang.org/api/packages/dump");
    packagesPath.write(dump);
    // auto dump = readText(packagesPath);
    Package[string] pkgs;

    foreach (ref pkg; parseJSON(dump).array.parallel)
    {
        auto repo = getRepo(pkg["repository"]);
        Package p = Package(
            pkg["name"].str,
            repo,
            getVersions(pkg["name"].str, pkg["versions"], repo.url));
        synchronized
        {
            pkgs[pkg["name"].str] = p;
        }
    }
    dubPkgsPath.write(pkgs.toJSON.toString(JSONOptions.doNotEscapeSlashes));

    generateNixExpression(pkgs);

}

void generateNixExpression(Package[string] pkgs)
{
    foreach (k, pkg; pkgs)
    {
        string p = "{";
        p ~= "  url = \"" ~ pkg.src.url ~ "\";";
        p ~= "  versions = {";
        foreach (j, ver; pkg.versions)
        {
            string v;
            v ~= "    \"" ~ ver.ver ~ "\" =  {";
            v ~= "      rev = \"" ~ ver.rev ~ "\";";
            v ~= "      sha256 = \"" ~ ver.hash ~ "\";";
            v ~= "    };";
            synchronized
            {
                p ~= v;
            }
        }
        p ~= "  };";
        p ~= "}";
        ("pkgs/dub/pkgs/" ~ pkg.name).mkdirRecurse();
        ("pkgs/dub/pkgs/" ~ pkg.name ~ "/default.nix")
            .write(p);
    }
}
