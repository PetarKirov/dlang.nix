import std.algorithm : startsWith;
import std.file : exists;
import std.format : format;
import std.process : executeShell, Config;
import std.string : splitLines, strip;
import std.stdio : stderr;

alias Version = string;
alias Platform = string;
alias Hash = string;
alias Url = string;

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
