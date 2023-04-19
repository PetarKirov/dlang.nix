{pkgs}:
with pkgs;
  mkShell {
    packages =
      [
        figlet
        nix-prefetch-git
        ldc
        dub
      ]
      ++ lib.optionals stdenv.hostPlatform.isx86 [
        dmd
      ];

    shellHook = ''
      figlet "Welcome  to Dlang  Nix"
      export DMD=ldmd2
    '';
  }
