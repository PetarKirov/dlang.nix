{ pkgs }:
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
  ] ++ lib.optionals stdenv.hostPlatform.isx86 [ dmd ];

  shellHook = ''
    figlet "Welcome  to Dlang  Nix"
    export DMD=ldmd2
  '';
}
