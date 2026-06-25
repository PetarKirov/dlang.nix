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
//
// The packer is deliberately identity-agnostic: it sees only a flat
// `WeightedItem` (a display `name`, a retargetable `attrPath`, a runner, and a
// `weight`). The rich `PackageBuildTarget` modelling lives at the boundary in
// `dlang_nix.ci.cli`, which projects down to these items.

import std.algorithm : filter, map, maxElement, sort, uniq;
import std.array : array, empty, join;

import dlang_nix.utils.conv : parseEnum;

@safe:

/// A Nix system double (`<arch>-<os>`). String-backed so each member *is* its
/// canonical double: it converts straight to `string` for flake refs and JSON
/// keys. Parse the reverse with `parseEnum!NixSystem`.
enum NixSystem : string {
    x86_64_linux = "x86_64-linux",
    aarch64_linux = "aarch64-linux",
    x86_64_darwin = "x86_64-darwin",
    aarch64_darwin = "aarch64-darwin",
    i686_linux = "i686-linux",
}

@("dlang_nix.ci.weights.nixSystem")
unittest {
    assert(NixSystem.x86_64_linux == "x86_64-linux");
    assert("aarch64-darwin".parseEnum!NixSystem == NixSystem.aarch64_darwin);
    assert("i686-linux".parseEnum!NixSystem == NixSystem.i686_linux);
    foreach (s; [NixSystem.x86_64_linux, NixSystem.aarch64_darwin, NixSystem.i686_linux])
        assert((cast(string) s).parseEnum!NixSystem == s); // round-trips
}

/// Whether a package was built with its test suite (`doCheck`). A checked build
/// can cost an order of magnitude more than a plain one, so weights are tracked
/// per variant. Backed by `bool` so it converts straight from a `doCheck` flag
/// (`cast(Variant) doCheck`); the member names double as the on-disk JSON keys.
enum Variant : bool {
    build, // doCheck = false
    test, // doCheck = true
}

/// Per-system weights: a `default` fallback plus `family -> variant -> weight`.
/// A family only lists the variant(s) it actually has.
struct SystemWeights {
    long defaultWeight = 1;
    long[Variant][string] families;
}

/// `system -> SystemWeights`.
alias Weights = SystemWeights[NixSystem];

/// Looks up a package's weight: its family's matching variant, else whatever
/// variant the family does have, else the system `default`, else `1` (so an
/// unknown family is never zero-weighted, which would let unbounded numbers of
/// them pack into a single job).
long weightOf(const Weights w, NixSystem system, string family, Variant variant) pure {
    const sys = system in w;
    if (sys is null)
        return 1;
    if (auto fam = family in sys.families) {
        if (auto v = variant in *fam)
            return *v;
        return fam.byValue.front; // family has only the other variant — close enough
    }
    return sys.defaultWeight;
}

@("dlang_nix.ci.weights.weightOf")
unittest {
    Weights w;
    SystemWeights sw;
    sw.defaultWeight = 6;
    sw.families["ldc"][Variant.build] = 87;
    sw.families["dub"][Variant.build] = 6;
    sw.families["dub"][Variant.test] = 139;
    w[NixSystem.x86_64_linux] = sw;

    assert(weightOf(w, NixSystem.x86_64_linux, "ldc", Variant.build) == 87);
    assert(weightOf(w, NixSystem.x86_64_linux, "dub", Variant.test) == 139);
    assert(weightOf(w, NixSystem.x86_64_linux, "dub", Variant.build) == 6);
    assert(weightOf(w, NixSystem.x86_64_linux, "dmd-binary", Variant.build) == 6); // default
    assert(weightOf(w, NixSystem.x86_64_linux, "ldc", Variant.test) == 87); // falls back to build
    assert(weightOf(w, NixSystem.aarch64_darwin, "ldc", Variant.test) == 1); // unknown system
}

/// One buildable atom, projected from a `PackageBuildTarget` for packing.
/// `name` is the display label (e.g. a job name); `attrPath` is the retargetable
/// flake attribute path (`packages.<system>.<attr>`, no `.#`).
struct WeightedItem {
    string name;
    string attrPath;
    NixSystem system;
    string os; // GH runner, e.g. "ubuntu-latest"
    long weight;
}

/// One CI job: a set of items built together on a runner.
struct Bin {
    string os;
    NixSystem system;
    WeightedItem[] items;
    long load;
}

/// First-Fit-Decreasing pack of one system's items into bins of capacity
/// `cap`. An item whose weight reaches `cap` fills its bin alone (nothing
/// else fits) — which is exactly "a heavy build gets a dedicated job" once the
/// caller sets `cap == maxWeight`.
///
/// FFD is a genuinely stateful algorithm (each placement depends on the running
/// loads of every prior bin), so this stays an explicit loop rather than a
/// range pipeline.
Bin[] packSystem(WeightedItem[] items, long cap) pure {
    auto sorted = items.dup.sort!((a, b) => a.weight > b.weight);
    Bin[] bins;
    outer: foreach (p; sorted) {
        foreach (ref b; bins)
            if (b.load + p.weight <= cap) {
                b.items ~= p;
                b.load += p.weight;
                continue outer;
            }
        bins ~= Bin(p.os, p.system, [p], p.weight);
    }
    return bins;
}

@("dlang_nix.ci.weights.packSystem")
unittest {
    WeightedItem wp(string a, long w) =>
        WeightedItem(a, a, NixSystem.x86_64_linux, "ubuntu-latest", w);

    // Heaviest (== cap) stays solo; the two 50s share one bin.
    auto bins = packSystem([wp("a", 100), wp("b", 50), wp("c", 50)], 100);
    assert(bins.length == 2);
    assert(bins[0].items.map!(i => i.name).array == ["a"] && bins[0].load == 100);
    assert(bins[1].load == 100); // b + c

    // Many light packages pack densely under a generous cap.
    auto light = packSystem([wp("a", 1), wp("b", 1), wp("c", 1), wp("d", 1), wp("e", 1)], 3);
    assert(light.length == 2); // [3] + [2]
    foreach (b; light)
        assert(b.load <= 3);
}

/// Groups items by system, packs each with capacity `= maxWeight` (so the
/// makespan is ~one longest build and the heaviest builds are isolated), and
/// guards the global job count: if it would exceed `capLimit`, capacities are
/// scaled up uniformly and everything is repacked until it fits.
Bin[] planMatrix(WeightedItem[] items, long capLimit = 240) pure {
    auto systems = items.map!(p => p.system).array.sort.uniq.array;
    for (long scale = 1;; scale++) {
        auto bins = systems
            .map!(sys => items.filter!(p => p.system == sys).array)
            .filter!(sp => !sp.empty)
            .map!(sp => packSystem(sp, sp.map!(p => p.weight).maxElement * scale))
            .join;
        if (bins.length <= capLimit || items.length <= capLimit)
            return bins;
    }
}

@("dlang_nix.ci.weights.planMatrix")
unittest {
    import std.algorithm : sort, map;
    import std.array : array, join;

    WeightedItem p(string a, NixSystem sys, long w) {
        const os = sys == NixSystem.x86_64_linux ? "ubuntu-latest" : "macos-latest";
        return WeightedItem(a, a, sys, os, w);
    }

    auto items = [
        p("ldc-1", NixSystem.x86_64_linux, 100),
        p("dmd-1", NixSystem.x86_64_linux, 80),
        p("dub-1", NixSystem.x86_64_linux, 9),
        p("dub-2", NixSystem.x86_64_linux, 9),
        p("ldc-binary-1", NixSystem.x86_64_linux, 1),
        p("ldc-2", NixSystem.aarch64_darwin, 100),
        p("dub-3", NixSystem.aarch64_darwin, 9),
    ];
    auto bins = planMatrix(items);

    // Every item appears exactly once (nothing lost or duplicated).
    auto packed = bins.map!(b => b.items.map!(i => i.name).array).join.array.sort.array;
    auto input = items.map!(p => p.name).array.sort.array;
    assert(packed == input);

    // No bin exceeds its system's capacity (== that system's max weight here).
    foreach (b; bins)
        assert(b.load <= 100);

    // The heavy compiler builds are isolated.
    foreach (b; bins)
        if (b.items.length == 1 && (b.items[0].name == "ldc-1" || b.items[0].name == "ldc-2"))
            assert(b.load >= 100);
}
