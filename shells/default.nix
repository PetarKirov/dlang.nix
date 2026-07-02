{ pkgs, config }:
with pkgs;
mkShell {
  packages = [
    figlet
    nix-eval-jobs
    jq
    nurl
    ldc
    dub
    dtools
    # Used by dlang-nix-fetcher when regenerating the dub-package tools'
    # source hashes and dub dependency locks (DCD, dfix, D-Scanner).
    git
    nix-prefetch-git

    (writeShellScriptBin "repl" ''nix repl --file "$REPO_ROOT/repl.nix"'')
  ] ++ lib.optionals stdenv.hostPlatform.isx86 [ dmd ];

  shellHook = ''
    export REPO_ROOT="$PWD"
    ${config.pre-commit.installationScript}
    figlet "Welcome  to Dlang  Nix"
  '';
}
