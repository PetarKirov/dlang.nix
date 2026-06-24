module dlang_nix.ci.weights;

// Build-time cost model + bin-packing for the CI build matrix.
//
// GitHub caps a job matrix at 256 entries, but the cold-cache build list is
// larger (every uncached, buildable `(package, system)`), so we pack several
// cheap packages into one job while letting heavy compiler builds keep their
// own. Packing is driven by a *relative build-time weight* per package; the
// weights themselves are measured by the `dlang-nix-fetcher ci calibrate`
// subcommand (see `dlang_nix.ci.cli`) and committed to
// `scripts/ci-build-weights.json`.

import std.algorithm : filter, map, maxElement, sort, uniq;
import std.array : array, empty;

@safe:

/// A package "family" is the attr name with its trailing `-<version>` removed.
/// Versions are sanitised to digits/underscores, so the version always starts
/// at the first `-` immediately followed by a digit. Names without such a
/// marker (the unversioned aliases like `ldc-bootstrap`) are returned as-is.
string baseFamily(string pkg) pure nothrow {
    foreach (i; 0 .. pkg.length)
        if (pkg[i] == '-' && i + 1 < pkg.length
            && pkg[i + 1] >= '0' && pkg[i + 1] <= '9')
            return pkg[0 .. i];
    return pkg;
}

unittest {
    assert(baseFamily("dmd-2_112_0") == "dmd");
    assert(baseFamily("dmd-binary-2_098_0") == "dmd-binary");
    assert(baseFamily("ldc-binary-1_42_0-beta2") == "ldc-binary");
    assert(baseFamily("dub-1_43_0-alpha-5efed36") == "dub");
    assert(baseFamily("ldc-bootstrap") == "ldc-bootstrap");
    assert(baseFamily("dub") == "dub");
}

/// Per-system weights: a `default` fallback plus `family -> variant -> weight`,
/// where the variant is `"build"` (doCheck=false) or `"test"` (doCheck=true).
/// A family only lists the variant(s) it actually has.
struct SystemWeights {
    long defaultWeight = 1;
    long[string][string] families;
}

/// `system -> SystemWeights`.
alias Weights = SystemWeights[string];

/// The variant key for a package's `doCheck`.
string variantKey(bool doCheck) pure nothrow => doCheck ? "test" : "build";

/// Looks up a package's weight: its family's matching variant, else whatever
/// variant the family does have, else the system `default`, else `1` (so an
/// unknown family is never zero-weighted, which would let unbounded numbers of
/// them pack into a single job).
long weightOf(const Weights w, string system, string family, bool doCheck) pure {
    const sys = system in w;
    if (sys is null)
        return 1;
    if (auto fam = family in sys.families) {
        if (auto v = variantKey(doCheck) in *fam)
            return *v;
        foreach (_, v; *fam)
            return v; // family has only the other variant — close enough
    }
    return sys.defaultWeight;
}

unittest {
    Weights w;
    SystemWeights sw;
    sw.defaultWeight = 6;
    sw.families["ldc"]["build"] = 87;
    sw.families["dub"]["build"] = 6;
    sw.families["dub"]["test"] = 139;
    w["x86_64-linux"] = sw;

    assert(weightOf(w, "x86_64-linux", "ldc", false) == 87);
    assert(weightOf(w, "x86_64-linux", "dub", true) == 139);
    assert(weightOf(w, "x86_64-linux", "dub", false) == 6);
    assert(weightOf(w, "x86_64-linux", "dmd-binary", false) == 6); // default
    assert(weightOf(w, "x86_64-linux", "ldc", true) == 87); // falls back to build
    assert(weightOf(w, "aarch64-darwin", "ldc", true) == 1); // unknown system
}

/// A package tagged with its runner, system and estimated build weight.
struct WeightedPkg {
    string attr; // e.g. "ldc-1_42_0"
    string system; // e.g. "x86_64-linux"
    string os; // GH runner, e.g. "ubuntu-latest"
    long weight;
}

/// One CI job: a set of packages built together on a runner.
struct Bin {
    string os;
    string system;
    string[] attrs;
    long load;
}

/// First-Fit-Decreasing pack of one system's packages into bins of capacity
/// `cap`. A package whose weight reaches `cap` fills its bin alone (nothing
/// else fits) — which is exactly "a heavy build gets a dedicated job" once the
/// caller sets `cap == maxWeight`.
Bin[] packSystem(WeightedPkg[] pkgs, long cap) pure {
    auto sorted = pkgs.dup;
    sorted.sort!((a, b) => a.weight > b.weight);
    Bin[] bins;
    outer: foreach (p; sorted) {
        foreach (ref b; bins)
            if (b.load + p.weight <= cap) {
                b.attrs ~= p.attr;
                b.load += p.weight;
                continue outer;
            }
        bins ~= Bin(p.os, p.system, [p.attr], p.weight);
    }
    return bins;
}

unittest {
    WeightedPkg wp(string a, long w) => WeightedPkg(a, "x86_64-linux", "ubuntu-latest", w);

    // Heaviest (== cap) stays solo; the two 50s share one bin.
    auto bins = packSystem([wp("a", 100), wp("b", 50), wp("c", 50)], 100);
    assert(bins.length == 2);
    assert(bins[0].attrs == ["a"] && bins[0].load == 100);
    assert(bins[1].load == 100); // b + c

    // Many light packages pack densely under a generous cap.
    auto light = packSystem([wp("a", 1), wp("b", 1), wp("c", 1), wp("d", 1), wp("e", 1)], 3);
    assert(light.length == 2); // [3] + [2]
    foreach (b; light)
        assert(b.load <= 3);
}

/// Groups packages by system, packs each with capacity `= maxWeight` (so the
/// makespan is ~one longest build and the heaviest builds are isolated), and
/// guards the global job count: if it would exceed `capLimit`, capacities are
/// scaled up uniformly and everything is repacked until it fits.
Bin[] planMatrix(WeightedPkg[] pkgs, long capLimit = 240) pure {
    auto systems = pkgs.map!(p => p.system).array.sort.uniq.array;
    for (long scale = 1;; scale++) {
        Bin[] bins;
        foreach (sys; systems) {
            auto sp = pkgs.filter!(p => p.system == sys).array;
            if (sp.empty)
                continue;
            const maxW = sp.map!(p => p.weight).maxElement;
            bins ~= packSystem(sp, maxW * scale);
        }
        if (bins.length <= capLimit || pkgs.length <= capLimit)
            return bins;
    }
}

unittest {
    import std.algorithm : sort, sum, map;
    import std.array : array, join;

    WeightedPkg p(string a, string sys, long w) {
        const os = sys == "x86_64-linux" ? "ubuntu-latest" : "macos-latest";
        return WeightedPkg(a, sys, os, w);
    }

    auto pkgs = [
        p("ldc-1", "x86_64-linux", 100),
        p("dmd-1", "x86_64-linux", 80),
        p("dub-1", "x86_64-linux", 9),
        p("dub-2", "x86_64-linux", 9),
        p("ldc-binary-1", "x86_64-linux", 1),
        p("ldc-2", "aarch64-darwin", 100),
        p("dub-3", "aarch64-darwin", 9),
    ];
    auto bins = planMatrix(pkgs);

    // Every package appears exactly once (nothing lost or duplicated).
    auto packed = bins.map!(b => b.attrs).join.array.sort.array;
    auto input = pkgs.map!(p => p.attr).array.sort.array;
    assert(packed == input);

    // No bin exceeds its system's capacity (== that system's max weight here).
    foreach (b; bins)
        assert(b.load <= 100);

    // The heavy compiler builds are isolated.
    foreach (b; bins)
        if (b.attrs.length == 1 && (b.attrs[0] == "ldc-1" || b.attrs[0] == "ldc-2"))
            assert(b.load >= 100);
}
