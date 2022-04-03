{pkgs ? import <nixpkgs> {}}:
with pkgs;
  mkShell {
    buildInputs = [
      figlet
      nix-prefetch-git
    ];

    shellHook = ''
      figlet "Welcome  to Dlang  Nix"
    '';
  }
