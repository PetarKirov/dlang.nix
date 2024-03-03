let
  dlang-nix = builtins.fetchGit {
    url = "https://github.com/PetarKirov/dlang.nix";
    ref = "main";
    rev = "22f68705314161f9b41e5a8828f6390aec745448";
  };

  pkgs = import <nixpkgs> {
    overlays = [(import dlang-nix).overlays.default];
  };
in
  pkgs.mkShell {
    packages = with pkgs; [
      dmd-2_104_2
      dub
    ];
  }
