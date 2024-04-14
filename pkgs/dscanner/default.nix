{
  lib,
  pkgs,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "dscanner";
  version = "0.15.2";

  src = fetchFromGitHub {
    owner = "dlang-community";
    repo = "D-Scanner";
    rev = "v${version}";
    hash = "sha256-TJ3aoU4q0lJdaL85LhuEJcYyZ7wOpGBwwmSz/bKnh9M=";
    fetchSubmodules = true; # Necessary for tests
  };

  dontDubTest = true;
  checkPhase = ''
    ${pkgs.gnumake} test
  '';

  meta = with lib; {
    description = "Swiss-army knife for D source code";
    homepage = "https://github.com/dlang-community/D-Scanner";
    license = licenses.boost;
    maintainers = with maintainers; [];
    mainProgram = "d-scanner";
    platforms = platforms.all;
  };
}
