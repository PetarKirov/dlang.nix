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

    # LDC master with dcompute's Vulkan target (ldc-developers/ldc#5132), its
    # shader stages, and the fixes they and WASI need on LLVM main: the
    # source of `ldc-vulkan` and `ldc-sparkles`.
    ldc-sparkles = {
      url = "git+https://github.com/PetarKirov/ldc?ref=sparkles/main&submodules=1";
      flake = false;
    };

    # Pinned nixpkgs that ships LLVM 22 (needed by the wasm32-wasip2 LDC fork,
    # which references llvm::Triple::WASIp1/2/3) plus the wasi32 cross sysroot and
    # compiler-rt. Matches the LDC WASI dev shell; only the x86_64-linux `ldc-wasm`
    # packages consume it.
    nixpkgs-wasm.url = "github:NixOS/nixpkgs/549bd84d6279f9852cae6225e372cc67fb91a4c1";

    # WASI component linker (produces wasm32-wasip2 components).
    wasm-component-ld = {
      url = "github:bytecodealliance/wasm-component-ld/v0.5.22";
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
