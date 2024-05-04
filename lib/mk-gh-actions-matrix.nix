{ lib, self, ... }:
{
  flake = {
    lib = rec {
      # See https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners/about-github-hosted-runners#standard-github-hosted-runners-for-public-repositories
      # See https://www.flyci.net/#pricing
      nixSystemToGHPlatform = {
        # GH-hosted runners:
        "x86_64-linux" = "ubuntu-latest";
        # "x86_64-darwin" = "macos-13"; - macos-13 is a 4 x86_64 vCPU / 14GB RAM
        # "x86_64-darwin" = "macos-14"; # - macos-14 is a 3 aarch64 vCPU / 7GB RAM (but it seems faster than the macos-13 one)
        # "aarch64-darwin" = "macos-14";

        # FlyCI-hosted runners:
        "x86_64-darwin" = "flyci-macos-large-latest-m1";
        "aarch64-darwin" = "flyci-macos-large-latest-m1";
      };

      inherit (import ./build-status.nix { inherit lib; }) getBuildStatus;

      allowedToFailMap = lib.pipe (mkGHActionsMatrix.include) [
        (builtins.groupBy (p: p.package))
        (builtins.mapAttrs (
          n: v: builtins.mapAttrs (s: ps: (builtins.head ps).allowedToFail) (builtins.groupBy (p: p.system) v)
        ))
      ];

      mkGHActionsMatrix = {
        include = lib.pipe (builtins.attrNames nixSystemToGHPlatform) [
          (builtins.concatMap (
            system:
            let
              platform = nixSystemToGHPlatform.${system};
            in
            map (
              package:
              let
                p = self.packages.${system}.${package};
              in
              {
                os = platform;
                allowedToFail =
                  !(p.passthru.buildStatus or (throw "${package} does not expose build status")).build;
                inherit system package;
                attrPath = "packages.${system}.${lib.strings.escapeNixIdentifier package}";
              }
            ) (builtins.attrNames self.packages.${system})
          ))
          (builtins.sort (
            a: b: if (a.package == b.package) then a.os == "ubuntu-latest" else a.package < b.package
          ))
        ];
      };
    };
  };
}
