import std.format : format;
import std.process : executeShell, Config;
import std.string : strip;
import std.stdio : stderr;

alias Version = string;
alias Platform = string;
alias Hash = string;
alias Url = string;

Hash prefech(bool dryRun, Url url, bool unpack = false) =>
    executeCommand(
        dryRun,
        `nix-hash --to-sri --type sha256 $( nix-prefetch-url %s "%s" )`
            .format(unpack ? "--unpack" : "", url)
    ).strip;


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
