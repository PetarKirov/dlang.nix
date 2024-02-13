{pkgs, ...}:
pkgs.mkShellNoCC {
  packages = with pkgs; [
    jq
    nix-eval-jobs
  ];
}
