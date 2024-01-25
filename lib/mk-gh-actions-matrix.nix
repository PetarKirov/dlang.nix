{
  lib,
  self,
  ...
}: {
  flake = {
    lib = rec {
      nixSystemToGHPlatform = {
        "ubuntu-latest" = "x86_64-linux";
        "macos-latest" = "x86_64-darwin";
        # not supported:
        # "macos-latest-xlarge" = "aarch64-darwin";
      };

      mkGHActionsMatrix = {
        include = lib.pipe (builtins.attrNames nixSystemToGHPlatform) [
          (builtins.concatMap
            (
              platform: let
                system = nixSystemToGHPlatform.${platform};
              in
                map (package: let
                  p = self.packages.${system}.${package};
                in {
                  os = platform;
                  allowedToFail = builtins.elem system (p.passthru.allowedToFailOn or []);
                  inherit system package;
                  attrPath = "packages.${system}.${package}";
                })
                (builtins.attrNames self.packages.${system})
            ))
          (builtins.sort (a: b:
            if (a.package == b.package)
            then a.os == "ubuntu-latest"
            else a.package < b.package))
        ];
      };
    };
  };
}
