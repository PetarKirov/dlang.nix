{pkgs ? import <nixpkgs> {}}: let
  dlang-nix = import (pkgs.fetchFromGitHub {
    owner = "PetarKirov";
    repo = "dlang.nix";
    rev = "3502a9f6dd2074c2f84d49baa5043f6601ca6407";
    hash = "sha256-djp8c2iONh+ET+wHbPLruNTuF7xSAYoMmwp1HfsrVTA=";
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
