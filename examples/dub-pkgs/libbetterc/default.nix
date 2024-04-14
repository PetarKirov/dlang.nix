{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "libbetterc";
  version = "unstable-2021-05-04";

  src = fetchFromGitHub {
    owner = "symmetryinvestments";
    repo = "libbetterc";
    rev = "06e56421b7ec3283a3535652762c7ea9210c588e";
    hash = "sha256-g7hZvBeriAI9EbgCZkqN9J2lxdgF/Cf6Aw8CDG58eks=";
  };

  meta = with lib; {
    description = "A tiny library for doing Dlang(betterc) stuff most likely for wasm";
    homepage = "https://github.com/symmetryinvestments/libbetterc";
    # license = licenses.unfree; # FIXME: nix-init did not found a license
    maintainers = with maintainers; [];
    mainProgram = "libbetterc";
    platforms = platforms.all;
  };
}
