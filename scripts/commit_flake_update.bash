#!/usr/bin/env bash

set -euo pipefail

if ! git config --get user.name >/dev/null 2>&1 || \
  [ "$(git config --get user.name)" = "" ] ||
  ! git config --get user.email >/dev/null 2>&1 || \
  [ "$(git config --get user.email)" = "" ]; then
  echo "git config user.{name,email} is not set - configuring"
  set -x
  git config --local user.email "out@space.com"
  git config --local user.name "beep boop"
fi

current_commit="$(git rev-parse HEAD)"
nix flake update --commit-lock-file
commit_after_update="$(git rev-parse HEAD)"

if [[ "$commit_after_update" = "$current_commit" ]]; then
  echo "All flake inputs are up to date."
  exit 0
fi

msg_file=./commit_msg_body.txt
{
  echo '```'
  git log -1 '--pretty=format:%b' | sed '1,2d'
  echo '```'
} > $msg_file

git commit --amend -F - <<EOF
chore(flake.lock): Update all Flake inputs ($(date -I))

$(cat $msg_file)
EOF

if [ -z "${CI+x}" ]; then
  rm -v $msg_file
fi
