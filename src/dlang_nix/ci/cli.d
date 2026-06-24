module dlang_nix.ci.cli;

// `dlang-nix-fetcher ci` — CI build-matrix helpers.
//
//   ci plan-matrix --weights <file>   (reads the package list as JSON on stdin)
//       Packs the buildable, uncached packages into a GitHub Actions job matrix
//       (`{"include":[{os,name,installables}]}`) by estimated build weight, so
//       the matrix stays under GitHub's 256-configuration cap. Pure packing
//       logic lives in `dlang_nix.ci.weights` (unit-tested).
//
//   ci calibrate [--remote-store <uri>] [--systems a,b] [--output <file>]
//       Measures per-(system, family, tests-enabled) build times and writes the
//       relative weights `plan-matrix` consumes.

import std.algorithm : canFind, map, filter, startsWith, endsWith;
import std.array : array, join, empty;
import std.conv : to;
import std.exception : enforce;
import std.getopt : getopt, arraySep;
import std.json : JSONValue, JSONType, parseJSON;
import std.stdio : stdin, stdout, stderr, writeln;
import std.string : strip;
static import std.file;

import dlang_nix.ci.weights;
import dlang_nix.utils.commands : executeCommand, executeTimed;
import dlang_nix.utils.json : toSortedPrettyJson;

/// Entry point for the `ci` subcommand. `args` starts with the subcommand
/// token (`["ci", "plan-matrix", ...]`), so `getopt` skips it like a program
/// name.
void runCi(string[] args) {
    enforce(args.length >= 2,
        "usage: dlang-nix-fetcher ci <plan-matrix|calibrate> [options]");
    switch (args[1]) {
        case "plan-matrix":
            planMatrixCmd(args[1 .. $]);
            break;
        case "calibrate":
            calibrateCmd(args[1 .. $]);
            break;
        default:
            enforce(false, "unknown ci subcommand: " ~ args[1]);
    }
}

// ---------------------------------------------------------------------------
// plan-matrix
// ---------------------------------------------------------------------------

private bool jsonBool(JSONValue v) =>
    v.type == JSONType.true_;

private string readAllStdin() {
    import std.array : appender;

    auto buf = appender!string;
    foreach (chunk; stdin.byChunk(1 << 16))
        buf.put(cast(const(char)[]) chunk);
    return buf.data;
}

/// Parses `scripts/ci-build-weights.json` into the `Weights` lookup table. Each
/// system maps a scalar `default` plus `family -> {build?, test?}` objects.
Weights parseWeights(string text) {
    Weights w;
    foreach (string system, body; parseJSON(text).object) {
        SystemWeights sw;
        foreach (string key, val; body.object) {
            if (key == "default")
                sw.defaultWeight = val.integer;
            else
                foreach (string variant, v; val.object)
                    sw.families[key][variant] = v.integer;
        }
        w[system] = sw;
    }
    return w;
}

private void planMatrixCmd(string[] args) {
    string weightsPath;
    args.getopt("weights", &weightsPath);
    enforce(weightsPath.length, "--weights <file> is required");

    const weights = parseWeights(std.file.readText(weightsPath));

    // stdin: array of { attr, system, os, isCached, allowedToFail, doCheck }.
    WeightedPkg[] buildable;
    foreach (j; parseJSON(readAllStdin).array) {
        auto o = j.object;
        if (jsonBool(o["isCached"]) || jsonBool(o["allowedToFail"]))
            continue;
        const attr = o["attr"].str;
        const system = o["system"].str;
        const os = o["os"].str;
        const doCheck = ("doCheck" in o) ? jsonBool(o["doCheck"]) : false;
        buildable ~= WeightedPkg(
            attr, system, os,
            weightOf(weights, system, baseFamily(attr), doCheck));
    }

    JSONValue[] include;
    foreach (b; planMatrix(buildable)) {
        const installables = b.attrs
            .map!(a => ".#packages." ~ b.system ~ "." ~ a)
            .join(" ");
        const name = b.attrs.length == 1
            ? b.attrs[0] ~ " | " ~ b.system
            : b.system ~ " · " ~ b.attrs.length.to!string ~ " pkgs";
        include ~= JSONValue([
            "os": JSONValue(b.os),
            "name": JSONValue(name),
            "installables": JSONValue(installables),
        ]);
    }
    // Compact single line — the matrix is consumed via `fromJSON` and echoed
    // into `$GITHUB_OUTPUT`.
    writeln(JSONValue(["include": JSONValue(include)]).toString);
}

// ---------------------------------------------------------------------------
// calibrate
// ---------------------------------------------------------------------------

private struct Rep {
    string family;
    string attr;
    bool x86Only;
}

// One representative per (family, tests-enabled) class. `dub` appears twice
// because its checked and build-only variants differ a lot in cost.
private enum Rep[] reps = [
    Rep("ldc", "ldc", false),
    Rep("dmd", "dmd", true),
    Rep("dub", "dub", false), // checked (the default alias)
    Rep("dub", "dub-1_0_0", false), // build-only
    Rep("ldc-binary", "ldc-binary-1_42_0", false),
    Rep("dmd-binary", "dmd-binary-2_098_0", true),
];

private void calibrateCmd(string[] args) {
    arraySep = ",";
    string remoteStore;
    string output = "scripts/ci-build-weights.json";
    string[] systems;
    args.getopt(
        "remote-store", &remoteStore,
        "output", &output,
        "systems", &systems,
    );
    if (systems.empty)
        systems = ["x86_64-linux", "x86_64-darwin", "aarch64-darwin"];

    // Merge into any existing file so a partial run (e.g. one system) keeps the
    // weights already measured for the others.
    Weights weights;
    if (std.file.exists(output))
        weights = parseWeights(std.file.readText(output));

    foreach (system; systems) {
        const isX86 = system.startsWith("x86_64") || system.startsWith("i686");
        // Linux builds locally; darwin builds on the (Rosetta-capable) remote.
        const storeArg = system.endsWith("linux") || remoteStore.empty
            ? "" : "--store " ~ remoteStore ~ " ";
        foreach (rep; reps) {
            if (rep.x86Only && !isX86)
                continue;
            const flake = ".#packages." ~ system ~ "." ~ rep.attr;

            // Presence + doCheck probe (also skips packages absent on this
            // platform, e.g. an old dub with no aarch64 host).
            const probe = executeCommand(false,
                "nix eval --json " ~ flake ~ ".doCheck 2>/dev/null");
            if (probe is null) {
                stderr.writefln("  skip %s (absent)", flake);
                continue;
            }
            const doCheck = probe.strip == "true";

            // Warm dependencies, then time a forced rebuild of just the target.
            // `--rebuild` reports "may not be deterministic" (non-zero) for
            // non-reproducible packages, but the build still ran and was timed,
            // so that case counts as a valid measurement.
            executeCommand(false,
                "nix build " ~ storeArg ~ "-L --no-link " ~ flake);
            const timed = executeTimed(
                "nix build " ~ storeArg ~ "-L --no-link --rebuild " ~ flake);
            const measured = timed.status == 0
                || canFind(timed.output, "may not be deterministic");
            if (!measured) {
                stderr.writefln("  build FAILED %s — skipping", flake);
                continue;
            }
            const secs = timed.elapsed.total!"seconds";
            weights.require(system, SystemWeights.init)
                .families.require(rep.family, null)[variantKey(doCheck)] =
                secs < 1 ? 1 : secs;
            stderr.writefln("  %s %s (doCheck=%s) -> %ss",
                system, rep.family, doCheck, secs);
        }
        // `default` (unknown family) = cheapest measured class in the system.
        long minW = long.max;
        if (auto sys = system in weights)
            foreach (_, variants; sys.families)
                foreach (_v, v; variants)
                    if (v < minW)
                        minW = v;
        if (minW != long.max)
            weights.require(system, SystemWeights.init).defaultWeight = minW;
    }

    std.file.write(output, toSortedPrettyJson(weightsToJson(weights)) ~ "\n");
    stderr.writefln("Wrote %s", output);
}

/// `Weights` -> JSONValue (scalar `default` + `family -> {variant: weight}`).
private JSONValue weightsToJson(Weights w) {
    JSONValue[string] outer;
    foreach (system, sw; w) {
        JSONValue[string] mid;
        mid["default"] = JSONValue(sw.defaultWeight);
        foreach (family, variants; sw.families) {
            JSONValue[string] inner;
            foreach (variant, v; variants)
                inner[variant] = JSONValue(v);
            mid[family] = JSONValue(inner);
        }
        outer[system] = JSONValue(mid);
    }
    return JSONValue(outer);
}
