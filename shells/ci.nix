{ pkgs, config, ... }:
pkgs.mkShellNoCC {
  packages =
    [ config.pre-commit.settings.package ]
    ++ (with pkgs; [
      jq
      nix-eval-jobs
    ]);

  shellHook = ''
    ${config.pre-commit.installationScript}
  '';
}
