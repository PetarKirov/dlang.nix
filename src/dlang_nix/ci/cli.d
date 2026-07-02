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
import dlang_nix.components : Families, baseFamily, PackageRelease, isPackageFamily;
import dlang_nix.utils.commands : executeCommand, executeTimed;
import dlang_nix.utils.conv : parseEnum;
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
                    sw.families[key][variant.to!Variant] = v.integer;
        }
        w[system.parseEnum!NixSystem] = sw;
    }
    return w;
}

/// A buildable matrix record as read from stdin JSON.
private struct Record {
    string attr;
    NixSystem system;
    string os;
    bool doCheck;
    string outPath; // derivation output path; dedups flake-attr aliases
}

/// A `PackageRelease` plus its build axes (`system`, `variant`). Projects to a
/// `WeightedItem` for the (identity-agnostic) packer.
struct PackageBuildTarget(C) if (isPackageFamily!C) {
    PackageRelease!C release;
    NixSystem system;
    Variant variant;

    long weight(in Weights w) const => weightOf(w, system, C.name, variant);
    // Retargetable attr path (no `.#`): callers prepend a flake ref.
    string flakeAttrPath() const => "packages." ~ cast(string) system ~ "." ~ release.toString;
}

/// Whether `attr` names a concrete versioned release of a known family, as
/// opposed to a bare flake-attr alias (`dmd`, `ldc-bootstrap`).
private bool isConcreteRelease(string attr) {
    const fam = baseFamily(attr);
    if (attr.length <= fam.length)
        return false; // no `-<version>` suffix
    bool known = false;
    static foreach (F; Families)
        if (fam == F.name)
            known = true;
    return known;
}

/// Collapses flake-attr aliases: records building the same derivation
/// (`(system, outPath)`) are deduplicated, preferring the concrete versioned
/// release over a bare alias — so `dmd-2_112_0` builds once and `dmd` is dropped.
/// Input order is preserved for the surviving representatives.
private Record[] dedup(Record[] records) {
    Record[string] best;
    string[] order;
    foreach (rec; records) {
        // No outPath (eval gap) ⇒ never collapse: key on the attr instead.
        const key = (cast(string) rec.system) ~ "\0"
            ~ (rec.outPath.length ? rec.outPath : "\x01" ~ rec.attr);
        if (auto existing = key in best) {
            if (isConcreteRelease(rec.attr) && !isConcreteRelease(existing.attr))
                *existing = rec;
        } else {
            best[key] = rec;
            order ~= key;
        }
    }
    return order.map!(k => best[k]).array;
}

/// Dispatches a record to its family and projects it to a `WeightedItem`.
private WeightedItem toItem(const Weights weights, Record rec) {
    const fam = baseFamily(rec.attr);
    const variant = cast(Variant) rec.doCheck;
    static foreach (F; Families) {{
        if (fam == F.name) {
            auto t = PackageBuildTarget!F(
                PackageRelease!F.parse(rec.attr), rec.system, variant);
            return WeightedItem(
                t.release.toString, t.flakeAttrPath, rec.system, rec.os, t.weight(weights));
        }
    }}
    // Orphan alias (no matching family): keep verbatim, default weight.
    return WeightedItem(
        rec.attr, "packages." ~ (cast(string) rec.system) ~ "." ~ rec.attr,
        rec.system, rec.os, weightOf(weights, rec.system, fam, variant));
}

private void planMatrixCmd(string[] args) {
    string weightsPath;
    args.getopt("weights", &weightsPath);
    enforce(weightsPath.length, "--weights <file> is required");

    const weights = parseWeights(std.file.readText(weightsPath));

    // stdin: array of { attr, system, os, isCached, allowedToFail, doCheck, outPath }.
    Record[] records;
    foreach (j; parseJSON(readAllStdin).array) {
        auto o = j.object;
        if (jsonBool(o["isCached"]) || jsonBool(o["allowedToFail"]))
            continue;
        Record rec;
        rec.attr = o["attr"].str;
        rec.system = o["system"].str.parseEnum!NixSystem;
        rec.os = o["os"].str;
        rec.doCheck = ("doCheck" in o) ? jsonBool(o["doCheck"]) : false;
        rec.outPath = ("outPath" in o) ? o["outPath"].str : "";
        records ~= rec;
    }

    auto items = dedup(records).map!(rec => toItem(weights, rec)).array;

    JSONValue[] include;
    foreach (b; planMatrix(items)) {
        // Prepend the current-flake ref `.#`; `attrPath` itself is retargetable.
        const installables = b.items.map!(i => ".#" ~ i.attrPath).join(" ");
        const string sys = b.system;
        const name = b.items.length == 1
            ? b.items[0].name ~ " | " ~ sys
            : sys ~ " · " ~ b.items.length.to!string ~ " pkgs";
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
    string[] systemArgs;
    args.getopt(
        "remote-store", &remoteStore,
        "output", &output,
        "systems", &systemArgs,
    );
    auto systems = systemArgs.empty
        ? [NixSystem.x86_64_linux, NixSystem.x86_64_darwin, NixSystem.aarch64_darwin]
        : systemArgs.map!(parseEnum!NixSystem).array;

    // Merge into any existing file so a partial run (e.g. one system) keeps the
    // weights already measured for the others.
    Weights weights;
    if (std.file.exists(output))
        weights = parseWeights(std.file.readText(output));

    foreach (system; systems) {
        const string sysStr = system;
        const isX86 = sysStr.startsWith("x86_64") || sysStr.startsWith("i686");
        // Linux builds locally; darwin builds on the (Rosetta-capable) remote.
        const storeArg = sysStr.endsWith("linux") || remoteStore.empty
            ? "" : "--store " ~ remoteStore ~ " ";
        foreach (rep; reps) {
            if (rep.x86Only && !isX86)
                continue;
            const flake = ".#packages." ~ sysStr ~ "." ~ rep.attr;

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
                .families.require(rep.family, null)[cast(Variant) doCheck] =
                secs < 1 ? 1 : secs;
            stderr.writefln("  %s %s (doCheck=%s) -> %ss",
                sysStr, rep.family, doCheck, secs);
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
                inner[variant.to!string] = JSONValue(v);
            mid[family] = JSONValue(inner);
        }
        outer[system] = JSONValue(mid);
    }
    return JSONValue(outer);
}
