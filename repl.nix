rec {
  system = builtins.currentSystem;
  flake = builtins.getFlake (builtins.toString ./.);
  pkgs = import flake.inputs.nixpkgs { };
  p = flake.packages.${system};
  lp = flake.legacyPackages.${system};
  lib = pkgs.lib;
  utils = flake.lib;
}
