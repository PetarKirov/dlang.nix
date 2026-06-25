# Architecture

This repository is a Nix flake that packages the three D toolchains — **DMD**,
**LDC**, and **dub** — across many versions and platforms, both from upstream
**binary** releases and from **source**. It has two cooperating halves:

1. **The Nix package layer** (`lib/`, `pkgs/`) — turns a catalog of pinned
   release hashes into a large `packages.<system>.<attr>` attrset, and derives
   the CI build matrix from it.
2. **The D tool** (`src/`, built as `dlang-nix-fetcher`) — a helper that
   (a) *prefetches* upstream releases to populate the hash catalogs, and
   (b) *packs* the CI build matrix into a bounded set of GitHub Actions jobs.

The seam between the halves is deliberately narrow and string-based:

- The D fetcher **writes** the `pkgs/*/supported-{source,binary}-versions.json`
  hash catalogs that the Nix layer **reads**.
- The Nix layer **emits** a package list (via `nix-eval-jobs` + `lib`
  helpers) that the D tool's `ci plan-matrix` **consumes** to produce the job
  matrix.

```
            ┌─────────────────────────── D tool (dlang-nix-fetcher) ──────────────────────────┐
 upstream   │  main.d runFetch!F                                   ci/cli.d plan-matrix        │
 releases ──┼─►  fetch hashes ──► supported-*.json                 dedup + weight + bin-pack    │
 (tags,     │        ▲                  │                                ▲           │          │
  tarballs) │        └ sparkles:versions│ (read)                  (pkg list)│        │ (matrix) │
            └───────────────────────────┼───────────────────────────────┬──┼────────┼──────────┘
                                        ▼                               │  │        ▼
                       ┌──────────── Nix layer ───────────────┐         │  │   .github/workflows
                       │ pkgs/*/version-catalog.nix            │         │  │   build matrix jobs
                       │ lib/version-catalog.nix genPkgVersions│──► self.packages.<sys>.<attr>
                       │ pkgs/default.nix                      │         ▲  │
                       │ lib/mk-gh-actions-matrix.nix          │─────────┘  │ (nix-eval-jobs)
                       │ pkgs/*/build-status.nix               │            │
                       └───────────────────────────────────────┘    scripts/ci-matrix.sh
```

---

## 1. The Nix package layer

### 1.1 Per-toolchain layout (`pkgs/<toolchain>/`)

Each of `pkgs/dmd/`, `pkgs/ldc/`, `pkgs/dub/` contains:

| File | Role |
| --- | --- |
| `supported-source-versions.json` | hash catalog for source builds |
| `supported-binary-versions.json` | hash catalog for upstream binary releases (dub has none) |
| `version-catalog.nix` | turns a `(version)` into a package *function* by reading the JSON |
| `generic.nix` / `binary.nix` / `default.nix` | the actual build recipes (source / binary) |
| `build-status.nix` | per-`(version, system)` build expectations |

### 1.2 The hash catalogs — `supported-{source,binary}-versions.json`

These are the source of truth for *which versions exist* and *how to fetch
them*. They are **machine-written** by the D fetcher (§3) and shaped
`{ version -> { component -> SRI-hash | null } }`:

- **Binary** (`dmd`/`ldc`): keys are download *platform* tokens, values are SRI
  hashes; `null` means "not published for that platform".
  ```jsonc
  // pkgs/ldc/supported-binary-versions.json
  "1.0.0": { "linux-x86_64": "sha256-…", "osx-arm64": null, … }
  ```
- **Source**:
  - `dmd`: one hash per upstream repo component (`dmd`, `phobos`, `tools`, and
    `druntime` only before 2.101 when it was a separate repo), plus a
    hand-maintained `host-d-compiler` naming the bootstrap host attr.
    ```jsonc
    "2.087.1": { "dmd": "sha256-…", "druntime": "sha256-…", "phobos": "sha256-…",
                 "tools": "sha256-…", "host-d-compiler": "ldc-binary-1_21_0" }
    ```
  - `ldc`: a single `src` tarball hash.
  - `dub`: the `dub` source hash plus an auto-pinned `rev` (the tag's commit),
    and an optional `d-compiler` host pin.
    ```jsonc
    "1.0.0": { "dub": "sha256-…", "rev": "b59af2b8…" }
    ```

The per-component **SRI hashes** and dub's **`rev`** are produced by the
fetcher; the **bootstrap cross-references** (`host-d-compiler`, `d-compiler`)
are maintained by hand.

### 1.3 `version-catalog.nix` — JSON → package function

`pkgs/<toolchain>/version-catalog.nix` exposes three values consumed by the
shared generator:

- `supportedVersions` — the parsed JSON (`{ source, binary }`).
- `getSourceVersion ourPkgs version` / `getBinaryVersion pkgs version` — look up
  the version's hashes and `import` the matching build recipe (`generic.nix` /
  `binary.nix` / `default.nix`), wiring bootstrap hosts (`host-d-compiler`,
  `d-compiler`) by name from `ourPkgs`. `getBinaryVersion = null` signals "no
  binary catalog" (dub).

### 1.4 `lib/version-catalog.nix` — `genPkgVersions`

The shared generator that turns a toolchain's catalog into attrs. For a
`pkgName`:

- **`flattened "binary" | "source"`** → `{ "<pname><suffix>-<sanitized-ver>" =
  drv }`, where the **source build takes no suffix** and the **binary build is
  suffixed `-binary`**, and `sanitizeVersion` replaces `.` with `_`
  (`2.112.0` → `2_112_0`). So `dmd-2_112_0` is source, `dmd-binary-2_098_0` is
  binary.
- **`hierarchical`** → `{ "<pname>" = { source = {ver→drv}; binary = {ver→drv} } }`
  (exposed as `legacyPackages`).
- `callWithExtras` injects only the extra args a recipe declares (`dCompiler`,
  `hostDCompiler`, `Foundation`); `filterBySystem` drops versions whose
  `meta.platforms` excludes the current system.

### 1.5 `pkgs/default.nix` — the package set

A `flake-parts` `perSystem` module that assembles `packages` from
`genPkgVersions … flattened …` plus a few **bare aliases** that pin a default
version (`ldc`, `dub`, `dmd`, and the bootstrap pointers `ldc-bootstrap`,
`dmd-bootstrap`). DMD is gated behind `pkgs.hostPlatform.isx86`. These aliases
are flake-attr pointers to a concrete versioned derivation — the D tool's
matrix dedup (§3.4) collapses them so each derivation builds once.

### 1.6 `build-status.nix` — expected build/check outcomes

`pkgs/<toolchain>/build-status.nix` is a `{ version -> { system -> { build,
check, skippedTests } } }` map encoding, per `(version, system)`:

- `build` — whether the package is *expected* to build (a `false` here makes CI
  treat a failure as non-fatal; see `allowedToFail` in §2.2).
- `check` — whether to run the upstream test suite (`doCheck`).
- `skippedTests` — individual upstream tests to disable (flaky/sandbox-hostile).

Each toolchain encodes this differently: `dmd` and `dub` compute it from
version *ranges* (`between start end`) with large curated `skippedTests` lists
and per-OS carve-outs; `ldc` is a sparse literal table of exceptions. Packages
expose the looked-up record via `passthru.buildStatus`, and the
default (when a version/system is absent) is `{ build = true; check = true;
skippedTests = []; }` (`lib/build-status.nix:getBuildStatus`).

---

## 2. `lib/` — flake library

`lib/default.nix` wires everything under `flake.lib`:

| Module | Provides |
| --- | --- |
| `version-utils.nix` | SemVer-ish helpers over `builtins.compareVersions` (`versionBetween[Inclusive]`, `sortVersions`, `latestVersion`) |
| `build-status.nix` | `getBuildStatus package version system` → the `build-status.nix` record (with the build-everything default) |
| `dc.nix` | DMD-frontend wrapper info for a compiler derivation (`dcToDmdMapping`, `normalizedName`, `ldcToDmdVersion`, `getDCInfo`) |
| `mk-gh-actions-matrix.nix` | the CI matrix inputs (below) |
| `version-catalog.nix` | `genPkgVersions` (§1.4) |

### 2.1 `nixSystemToGHPlatform`

The closed set of CI systems and their GitHub runners:
`x86_64-linux → ubuntu-latest`, `x86_64-darwin → macos-26-intel`,
`aarch64-darwin → macos-latest`. (Other systems appear in `build-status.nix`
but only these three are built in CI.)

### 2.2 `mkGHActionsMatrix.include` and the maps

`mkGHActionsMatrix.include` is the cartesian product of the three CI systems and
every attr in `self.packages.<system>`, each entry carrying:

- `os` (runner), `system`, `package` (attr name), `attrPath`,
- `allowedToFail = !buildStatus.build` (packages not expected to build may fail
  without failing CI),
- `doCheck = p.doCheck or false`.

Two regroupings feed the D tool, both shaped `{ package -> { system -> flag } }`:

- **`doCheckMap`** — drives per-package weight selection (a test-running build is
  much heavier than a build-only one).
- **`allowedToFailMap`** — lets `plan-matrix` drop packages that needn't build.

---

## 3. The D tool — `src/` (`dlang-nix-fetcher`)

A single executable (`src/main.d`) with two roles. It depends on the
`sparkles:versions` dub package (see `dub.sdl`) for typed version
parsing/ordering. Module layout:

```
src/main.d                    entry point + the release-prefetcher (runFetch!F)
src/dlang_nix/
  components.d                the PackageFamily concept, the families, PackageRelease
  utils/conv.d                parseEnum (value-matching enum parser)
  utils/commands.d            shell-out helpers, git tag fetch, typed version resolvers
  utils/json.d                hash-table ⇄ sorted-pretty JSON
  ci/weights.d                cost model + First-Fit-Decreasing bin-packer
  ci/cli.d                    `ci plan-matrix` / `ci calibrate`
```

### 3.1 The `PackageFamily` concept (`components.d`)

The toolchain "families" are modelled as a compile-time concept, in the spirit
of `sparkles:versions` (a plain struct + a `static assert`, no base class, no
registration):

```d
enum isPackageFamily(C) = is(typeof(checkPackageFamily!C)); // name, VersionType, url, platforms, …
```

Five family structs each carry a `name` (the attr/pname prefix — the seam with
the Nix layer §1.4), a typed `VersionType`, the static fetch surface
(`url`, `platforms`, `supportedVersionsFile`, `tagsRepo`, `defaultVersions`,
`unpackingNeed`), and optional capabilities:

| Struct | `name` | `VersionType` | notes |
| --- | --- | --- | --- |
| `DmdBinary` | `dmd-binary` | `Dmd` | downloads.dlang.org tarball |
| `Dmd` | `dmd` | `Dmd` | github source, unpack |
| `LdcBinary` | `ldc-binary` | `SemVer` | github release tarball |
| `Ldc` | `ldc` | `SemVer` | github `-src.tar.gz` |
| `Dub` | `dub` | `SemVer` | github source; `pinsRev` capability |

`alias Families = AliasSeq!(…)` is the **single registry** — the `--component`
CLI tokens, dispatch, and allowed-value help are all inferred from `F.name`.
The `Dmd` *version scheme* (zero-padded 3-digit minor, e.g. `2.098.0`) and
`SemVer` differ, which is why the scheme is per-family.

`PackageRelease!C` adds a concrete version to a family: it stores the verbatim
underscore version (`rawVersion`) for an exact attr round-trip plus a
best-effort typed `ver` for ordering. `baseFamily(attr)` strips the trailing
`-<version>` to recover the family name.

### 3.2 The prefetcher (`main.d` `runFetch!F`)

`dlang-nix-fetcher --component <name> [--versions … | --first-version … --last-version …]`
resolves the requested versions, fetches each `(version, platform)` with
`nix-prefetch-url`, and merges the resulting SRI hashes into the family's
`supportedVersionsFile`. The pipeline is **typed end-to-end** on
`F.VersionType`; `string` appears only at the CLI boundary (`parseLoose`) and
the JSON boundary (`toString` keys). For `--first/--last`,
`resolveVersionRange!V` (`utils/commands.d`) walks `git ls-remote` tags and
keeps the latest patch per minor; families with the `pinsRev` capability (dub)
also resolve each tag's commit via `resolveTagRevs!V`. `utils/json.d`
(`mergeHashesIntoJson`) renders the merged table back to version-sorted JSON.

### 3.3 The cost model + packer (`ci/weights.d`)

GitHub caps a job matrix at 256 entries, but the cold-cache build list (every
uncached buildable `(package, system)`) is larger. `weights.d` defines:

- `NixSystem`, `Variant` (`build`/`test`), and `Weights = SystemWeights[NixSystem]`
  — a `family -> variant -> weight` table loaded from
  `scripts/ci-build-weights.json` (measured by `ci calibrate`).
- `weightOf(weights, system, family, variant)` — the per-package cost.
- `packSystem` — **First-Fit-Decreasing** packing into bins of capacity
  `cap`; a package whose weight reaches `cap` fills its bin alone (a heavy
  compiler build gets a dedicated job).
- `planMatrix` — packs each system with `cap = maxWeight`, scaling capacities up
  uniformly and repacking if the job count would exceed the limit.

The packer is deliberately **identity-agnostic**: it operates on a flat
`WeightedItem { name, attrPath, system, os, weight }`, never on the rich types.

### 3.4 `ci plan-matrix` / `ci calibrate` (`ci/cli.d`)

`plan-matrix` reads the package list as JSON on stdin and:

1. **filters** out cached / allowed-to-fail records;
2. **dedups** by derivation identity `(system, outPath)`, preferring the attr
   that parses to a concrete `PackageRelease` — so the `dmd` alias collapses
   into `dmd-2_112_0` and the derivation is built once;
3. **dispatches** each surviving attr through `Families` (matching
   `baseFamily(attr) == F.name`) into a typed `PackageBuildTarget!F`, whose
   `flakeAttrPath` is the *retargetable* `packages.<system>.<attr>` (no `.#`);
4. **projects** to `WeightedItem` and runs `planMatrix`;
5. **emits** `{ include: [ { os, name, installables } ] }`, prepending `.#` to
   each `attrPath`. Several small packages share one job's `installables`.

`calibrate` measures the per-`(system, family, variant)` build times (timing a
forced rebuild of representative packages) and writes
`scripts/ci-build-weights.json`.

---

## 4. `scripts/ci-matrix.sh` and the CI flow

`ci-matrix.sh` is the glue invoked by `.github/generate-matrix`:

1. **`eval_packages_to_json`** — runs `nix-eval-jobs` over `packages` for all
   systems and joins it with `lib.allowedToFailMap`, `lib.doCheckMap`, and
   `lib.nixSystemToGHPlatform`, producing one record per `(package, system)`
   with `{ package, system, os, isCached, allowedToFail, doCheck, outPath,
   cache_url, … }`. The `outPath` (the derivation's `outputs.out`) is the
   dedup key.
2. **`save_gh_ci_matrix`** — projects those records to
   `{ attr, system, os, isCached, allowedToFail, doCheck, outPath }` and pipes
   them through `dlang-nix-fetcher ci plan-matrix --weights
   scripts/ci-build-weights.json`, writing the resulting matrix to
   `$GITHUB_OUTPUT`.
3. **`convert_nix_eval_to_table_summary_json`** — renders the per-package cache
   status table posted as a PR comment.

In `.github/workflows/ci.yml`, the `generate-matrix` job's output becomes the
`build` job's `strategy.matrix`; each build job runs
`nix build -L --no-link --keep-going ${{ matrix.installables }}` (so one failure
in a batched job still builds/caches the rest), and a final `results` job fails
CI if any required build failed.

---

## 5. Cross-cutting conventions

- **The `name`/attr/weight-key correspondence.** A family's `F.name`
  (`dmd-binary`), the Nix attr prefix from `genPkgVersions … flattened`
  (`dmd-binary-2_098_0`), and the weight-table key in
  `ci-build-weights.json` are the *same string*. `baseFamily` recovers it from
  any attr.
- **Source vs binary naming.** Source builds are unsuffixed
  (`dmd`, `ldc`, `dub`); the binary variant is `-binary`.
- **Two version schemes.** DMD uses zero-padded 3-digit minors (`2.098.0`);
  LDC/dub use canonical SemVer. The scheme lives on the family
  (`F.VersionType`), so versions parse/sort correctly on both sides of the seam.
- **Version string sanitisation.** Dots become underscores in attr names
  (`2.112.0` ↔ `2_112_0`); `PackageRelease` round-trips this exactly, and Nix's
  `sanitizeVersion` does the forward direction.
