#!/usr/bin/env bash

set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
result_dir="$root_dir/.result"
gc_roots_dir="$result_dir/gc-roots"

# shellcheck source=./system-info.sh
source "$root_dir/scripts/system-info.sh"

create_result_dirs() {
  mkdir -p "$result_dir" "$gc_roots_dir"
}

nix_eval_jobs() {
  flake_attr="$1"

  get_platform
  get_available_memory_mb
  get_nix_eval_worker_count

  {
    (
      set -x
      nix-eval-jobs \
        --quiet \
        --option warn-dirty false \
        --check-cache-status \
        --gc-roots-dir "$gc_roots_dir" \
        --workers "$max_workers" \
        --max-memory-size "$max_memory_mb" \
        --flake "$root_dir#$flake_attr"
    ) \
      | tee /dev/fd/3 \
      | stdbuf -i0 -o0 -e0 jq --color-output -c '{ attr, isCached, out: .outputs.out }' > /dev/stderr
  } 3>&1 2> >(
    grep -vP "(SQLite database|warning: unknown setting 'allowed-users'|warning: unknown setting 'trusted-users')" \
    >&2
  )
}

nix_eval_for_all_systems() {
  flake_pre="$1"
  flake_post="${2:+.$2}"

  systems=( {x86_64-linux,{x86_64,aarch64}-darwin} )

  for system in "${systems[@]}"; do
    nix_eval_jobs "${flake_pre}.${system}${flake_post}"
  done
}

