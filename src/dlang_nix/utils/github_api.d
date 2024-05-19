module dlang_nix.utils.github_api;

import std.algorithm : filter, map;
import std.array : array;
import std.format : format;
import std.json : JSONValue, parseJSON;
import std.process : environment;

import semver : SemVer, VersionPart;

import dlang_nix.utils.api : fetchPagedResponse, getNextPageFromLinkHeader;

string[] getGitHubRepoTags(string repo, bool includePrereleases = false, string apiKey = environment["GH_TOKEN"])
{
    string getGHPage(int page)
    {
        return "https://api.github.com/repos/%s/tags?per_page=100&page=%s"
            .format(repo, page);
    }

    return fetchPagedResponse!(JSONValue)(
        getGHPage(1),
        [ "Authorization": "Bearer " ~ apiKey ],
        (const(char)[] rawResponse) => rawResponse.parseJSON.array,
        (response, headers) => getNextPageFromLinkHeader(headers),
    )
        .map!(j => j.object["name"].str)
        .filter!(ver => SemVer(ver).isValid)
        .filter!(ver => includePrereleases || SemVer(ver).isStable)
        .array;
}
