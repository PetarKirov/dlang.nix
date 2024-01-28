{pkgs ? import <nixpkgs> {}}: let
  dlang-nix = import (pkgs.fetchFromGitHub {
    owner = "PetarKirov";
    repo = "dlang.nix";
    rev = "b9b7ef694329835bec97aa78e93757c3fbde8e13";
    hash = "sha256-zNvuU0DFSfCtQPFQ3rxri2e3mlMzLtJB/qaDsS0i9Gg=";
  });

  dpkgs = dlang-nix.packages."${pkgs.system}";
in
  pkgs.mkShell {
    packages = [
      pkgs.figlet
      dpkgs.dmd
      dpkgs.dub
    ];

    shellHook = ''
      figlet "Hello, D world!"
    '';
  }
