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

    # LLVM main with the SPIR-V fixes dcompute's Vulkan target needs, one
    # commit each on PetarKirov/llvm-project `sparkles/main`: the source of
    # `llvm-spirv-vulkan`. A shallow clone, not a GitHub tarball: GitHub fills in
    # the `export-subst` placeholders of `.git_archival.txt` when it builds the
    # tarball, so Nix versions disagree on its hash (CI's 2.35 rejected 2.32's).
    llvm-sparkles = {
      url = "git+https://github.com/PetarKirov/llvm-project?ref=sparkles/main&shallow=1";
      flake = false;
    };

    # LDC master with dcompute's Vulkan target (ldc-developers/ldc#5132), its
    # shader stages, and the fixes they and WASI need on LLVM main: the
    # source of `ldc-vulkan` and `ldc-sparkles`.
    ldc-sparkles = {
      url = "git+https://github.com/PetarKirov/ldc?ref=sparkles/main&submodules=1";
      flake = false;
    };

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
              # nixpkgs' `nixfmt-rfc-style` is now an alias of `nixfmt`, and
              # warns; the hook's default package names the alias.
              package = pkgs.nixfmt;
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
