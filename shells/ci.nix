{ pkgs, config, ... }:
pkgs.mkShellNoCC {
  packages =
    [
      config.pre-commit.settings.package
      (pkgs.callPackage ../pkgs/dlang-nix-fetcher { })
    ]
    ++ (with pkgs; [
      jq
      nix-eval-jobs
    ]);

  shellHook = ''
    ${config.pre-commit.installationScript}
  '';
}
