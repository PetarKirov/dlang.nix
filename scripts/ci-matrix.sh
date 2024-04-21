#!/usr/bin/env bash

set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"

# shellcheck source=./nix-eval-jobs.sh
source "$root_dir/scripts/nix-eval-jobs.sh"

eval_packages_to_json() {
  flake_attr_pre="${1:-packages}"
  flake_attr_post="${2:-}"

  cachix_url="https://${CACHIX_CACHE}.cachix.org"

  nix eval --json .#lib.allowedToFailMap > "${result_dir}/allowed-to-fail.json"

  nix_eval_for_all_systems "$flake_attr_pre" "$flake_attr_post" \
    | cat "${result_dir}/allowed-to-fail.json" - \
    | jq -sr '
    .[0] as $allowed_to_fail
    | .[1:] as $nix_eval_results
    | {
      "x86_64-linux": "ubuntu-latest",
      "x86_64-darwin": "macos-13",
      "aarch64-darwin": "flyci-macos-large-latest-m1"
    } as $system_to_gh_platform
    | $nix_eval_results
    | map({
      package: .attr,
      attrPath: "\(.system).\(.attr)",
      allowedToFail: $allowed_to_fail[.attr][.system],
      isCached,
      system,
      cache_url: .outputs.out
        | "'"$cachix_url"'/\(match("^\/nix\/store\/([^-]+)-").captures[0].string).narinfo",
      os: $system_to_gh_platform[.system]
    })
      | sort_by(.package | ascii_downcase)
  '
}

save_gh_ci_matrix() {
  packages_to_build=$(echo "$packages" | jq -c '. | map(select((.isCached | not) and (.allowedToFail | not)))')
  matrix='{"include":'"$packages_to_build"'}'
  filename=''
  if [ "${IS_INITIAL:-true}" = "true" ]; then
    filename='matrix-pre.json'
  else
    filename='matrix-post.json'
  fi
  echo "$matrix" > "$result_dir/$filename"
  echo "matrix=$matrix" >> "${GITHUB_OUTPUT:-${result_dir}/gh-output.env}"
}

convert_nix_eval_to_table_summary_json() {
  is_initial="${IS_INITIAL:-true}"
  echo "$packages" \
  | jq '
    def getStatus(pkg; key):
      if (pkg | has(key))
      then (
        if pkg[key].isCached
        then "[✅ cached](\(pkg[key].cache_url))"
        else (
          if pkg[key].allowedToFail
          then "🚧 known to fail (disabled)"
          else (
            if "'"$is_initial"'" == "true"
            then "⏳ building..."
            else "❌ build failed"
            end
          ) end
        ) end
      ) else "🚫 not supported"
      end;

    group_by(.package)
    | map(
      . | INDEX(.system) as $pkg
      | .[0].package as $name
      | {
        package: $name,
        "x86_64-linux": getStatus($pkg; "x86_64-linux"),
        "x86_64-darwin": getStatus($pkg; "x86_64-darwin"),
        "aarch64-darwin": getStatus($pkg; "aarch64-darwin"),
      }
    )
    | sort_by(.package)'
}

printTableForCacheStatus() {
  create_result_dirs
  packages="$(eval_packages_to_json "$@")"

  save_gh_ci_matrix

  {
    echo "Thanks for your Pull Request!"
    echo
    echo "Below you will find a summary of the cachix status of each package, for each supported platform."
    echo
    # shellcheck disable=SC2016
    echo '| package | `x86_64-linux` | `x86_64-darwin` | `aarch64-darwin` |'
    echo '| ------- | -------------- | --------------- | ---------------- |'
    convert_nix_eval_to_table_summary_json | jq -r '
      .[] | "| `\(.package)` | \(.["x86_64-linux"]) | \(.["x86_64-darwin"]) | \(.["aarch64-darwin"]) |"
    '
    echo
  } > "$result_dir/comment.md"
}

printTableForCacheStatus "$@"

