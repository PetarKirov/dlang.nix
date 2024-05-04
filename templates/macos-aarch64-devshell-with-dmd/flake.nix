{
  description = "My D project";

  inputs = {
    dlang-nix.url = "github:PetarKirov/dlang-nix";

    nixpkgs.follows = "dlang-nix/nixpkgs";

    # Check https://flake.parts/ for more info
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      perSystem =
        { inputs', pkgs, ... }:
        {
          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.figlet
              inputs.dlang-nix.packages.x86_64-darwin.dmd
              inputs'.dlang-nix.packages.dub
            ];

            shellHook = ''
              figlet "Hello, D world!"
            '';
          };
        };
    };
}
