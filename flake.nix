{
  description = "Nix packages for D projects";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.simpleFlake {
      inherit self nixpkgs;
      name = "dlang-nix";
      shell = ./shell.nix;
    };
}
