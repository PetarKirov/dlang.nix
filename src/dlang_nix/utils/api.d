module dlang_nix.utils.api;

import std.algorithm : find, map, splitter, startsWith;
import std.array : array;
import std.string : strip;
import std.typecons : Tuple;

import dlang_nix.utils.ranges : firstOrDefault, tryGet;

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
        .splitter(",")
        .map!(x => x.splitter(";").map!(part => part.strip).array)
        .map!(parts => Link(
            parts[0][1 .. $ - 1], // "<URL>"" -> "URL"
            parts[1 .. $]
                .find!((string p) => p.startsWith("rel"))
                .map!(p => p[5 .. $ - 1]) // `rel="value"` -> `"value"`
                .firstOrDefault!"!!a"
        ))
        .array;
}
