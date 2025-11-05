{
  description = "Nix packages for D projects";

  nixConfig = {
    extra-substituters = [ "https://dlang-community.cachix.org" ];
    extra-trusted-public-keys = [
      "dlang-community.cachix.org-1:eAX1RqX4PjTDPCAp/TvcZP+DYBco2nJBackkAJ2BsDQ="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-compat.url = "github:edolstra/flake-compat";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      git-hooks-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      imports = [
        git-hooks-nix.flakeModule

        ./pkgs
        ./lib
      ];

      perSystem =
        { pkgs, config, ... }:
        {
          devShells.default = import ./shells/default.nix { inherit pkgs config; };
          devShells.ci = import ./shells/ci.nix { inherit pkgs config; };

          pre-commit.settings.hooks = {
            editorconfig-checker.enable = true;
            nixfmt-rfc-style = {
              enable = true;
            };
          };
        };

      flake.templates =
        let
          lib = nixpkgs.lib;
          allTemplates = lib.pipe (builtins.readDir ./templates) [
            (lib.filterAttrs (k: v: v == "directory"))
            (builtins.mapAttrs (
              k: v: rec {
                path = ./templates + "/${k}";
                description = lib.removeSuffix "\n" (builtins.readFile (path + "/description.txt"));
              }
            ))
          ];
        in
        allTemplates;
    };
}
