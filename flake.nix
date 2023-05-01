{
  description = "Nix packages for D projects";

  nixConfig = {
    extra-substituters = "https://dlang-community.cachix.org";
    extra-trusted-public-keys = "dlang-community.cachix.org-1:eAX1RqX4PjTDPCAp/TvcZP+DYBco2nJBackkAJ2BsDQ=";
  };

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
      imports = [./pkgs];
      perSystem = {final, ...}: {
        devShells.default = import ./shell.nix {pkgs = final;};
      };
    };
}
