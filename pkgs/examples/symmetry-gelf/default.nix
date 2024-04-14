{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "symmetry-gelf";
  version = "unstable-2019-09-15";

  src = fetchFromGitHub {
    owner = "symmetryinvestments";
    repo = "symmetry-gelf";
    rev = "cb235c148177ad014b632801f3e663e5f45dbf09";
    hash = "sha256-7sPD1QIYPsSLogZNS/UMxWdwxtVwecViG2DC4V2NPI4=";
  };

  dontDubTest = true;

  meta = with lib; {
    description = "Gelf (graylog) plugin for std.experimental.logg";
    homepage = "https://github.com/symmetryinvestments/symmetry-gelf";
    # license = licenses.unfree; # FIXME: nix-init did not found a license
    maintainers = with maintainers; [];
    mainProgram = "symmetry-gelf";
    platforms = platforms.all;
  };
}
