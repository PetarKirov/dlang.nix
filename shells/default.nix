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

    (writeShellScriptBin "repl" ''nix repl --file "$REPO_ROOT/repl.nix"'')
  ]
  # This flake's DMD: nixpkgs' bootstraps through a 2.090.1 binary that
  # crashes on glibc 2.44.
  ++ lib.optionals stdenv.hostPlatform.isx86 [ config.packages.dmd-2_112_1 ];

  shellHook = ''
    export REPO_ROOT="$PWD"
    ${config.pre-commit.installationScript}
    figlet "Welcome  to Dlang  Nix"
  '';
}
