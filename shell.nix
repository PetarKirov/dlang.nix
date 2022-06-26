{pkgs ? import <nixpkgs> {}}:
with pkgs;
  mkShell {
    buildInputs = [
      figlet
      nix-prefetch-git
      dmd
      ldc
      dub
    ];

    shellHook = ''
      figlet "Welcome  to Dlang  Nix"
      export DMD=ldmd2
    '';
  }
