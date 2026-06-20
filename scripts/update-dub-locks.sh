#!/usr/bin/env bash
#
# Regenerate per-version dub-lock.json files for the dlang-community tools
# (DCD, dfix, D-Scanner) using nixpkgs' `dub-to-nix`.
#
# `buildDubPackage` needs a nixpkgs dependency lock (`dub-lock.json`) per
# version, in addition to the source-tarball hash that `dlang-nix-fetcher`
# already records in `pkgs/<tool>/supported-source-versions.json`. For each
# requested version this clones the matching git tag, makes sure a
# `dub.selections.json` exists (running `dub upgrade` when it doesn't — dfix
# ships none), runs `dub-to-nix`, and writes the result to
# `pkgs/<tool>/locks/<version>.json`. Versions whose lock cannot be generated
# are logged and skipped (leave them out of the matrix / mark them
# `build = false` in `pkgs/<tool>/build-status.nix`).
#
# Usage:
#   scripts/update-dub-locks.sh <dcd|dfix|dscanner> [version...]
#   scripts/update-dub-locks.sh dscanner            # every version in the JSON
#   scripts/update-dub-locks.sh dcd 0.16.2 0.15.2   # specific versions
#
# Requires a Nix with flakes; all build tools are pulled on demand via
# `nix shell`.
set -uo pipefail

tool=${1:?usage: update-dub-locks.sh <dcd|dfix|dscanner> [version...]}
shift || true

case "$tool" in
  dcd)      repo="dlang-community/DCD" ;;
  dfix)     repo="dlang-community/dfix" ;;
  dscanner) repo="dlang-community/D-Scanner" ;;
  *) echo "unknown tool: $tool (expected dcd|dfix|dscanner)" >&2; exit 1 ;;
esac

repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
pkg_dir="$repo_root/pkgs/$tool"
locks_dir="$pkg_dir/locks"
versions_json="$pkg_dir/supported-source-versions.json"

if [ "$#" -gt 0 ]; then
  versions=("$@")
else
  [ -f "$versions_json" ] || {
    echo "no $versions_json found; run the fetcher first or pass versions explicitly" >&2
    exit 1
  }
  mapfile -t versions < <(nix shell nixpkgs#jq -c jq -r 'keys[]' "$versions_json")
fi

mkdir -p "$locks_dir"

failed=()
for v in "${versions[@]}"; do
  echo "==> $tool v$v"
  work=$(mktemp -d)
  if ! git clone --quiet --depth 1 --branch "v$v" "https://github.com/$repo" "$work/src"; then
    echo "  clone of v$v failed" >&2
    failed+=("$v")
    rm -rf "$work"
    continue
  fi

  if (
    cd "$work/src" || exit 1
    if [ ! -f dub.selections.json ]; then
      echo "  no dub.selections.json -> dub upgrade" >&2
      nix shell nixpkgs#dub "$repo_root#ldc" -c dub upgrade >&2
    fi
    nix shell nixpkgs#dub-to-nix nixpkgs#dub nixpkgs#nix-prefetch-git "$repo_root#ldc" \
      -c dub-to-nix
  ) > "$locks_dir/$v.json.tmp" 2> "$work/err.log" && [ -s "$locks_dir/$v.json.tmp" ]; then
    mv "$locks_dir/$v.json.tmp" "$locks_dir/$v.json"
    echo "  wrote pkgs/$tool/locks/$v.json"
  else
    echo "  FAILED to generate lock for v$v:" >&2
    sed 's/^/    /' "$work/err.log" >&2
    rm -f "$locks_dir/$v.json.tmp"
    failed+=("$v")
  fi
  rm -rf "$work"
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "" >&2
  echo "Lock generation failed/skipped for: ${failed[*]}" >&2
  exit 1
fi
