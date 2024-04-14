{
  lib,
  buildDubPackage,
  fetchFromGitHub,
  meson,
  ninja,
}:
buildDubPackage rec {
  pname = "mir-algorithm";
  version = "3.22.0";

  src = fetchFromGitHub {
    owner = "libmir";
    repo = "mir-algorithm";
    rev = "v${version}";
    hash = "sha256-j25jPpA4MLSrsUyBiLYMZXbzAxE6QRC5SRoYtPAJesI=";
  };

  dubSelections = ./dub.selections.json;

  meta = with lib; {
    description = "Dlang Core Library";
    homepage = "https://github.com/libmir/mir-algorithm";
    license = licenses.asl20;
    maintainers = with maintainers; [];
    mainProgram = "mir-algorithm";
    platforms = platforms.all;
  };
}
