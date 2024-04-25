{
  lib,
  buildDubPackage,
  fetchFromGitHub,
  pkgs,
}:
buildDubPackage rec {
  pname = "dpp";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "atilaneves";
    repo = "dpp";
    rev = "v${version}";
    hash = "sha256-8/nfsh0KuwF1O0tvsdYoSeccsANU+Xoj9z4Z5h82Iy0=";
  };

  buildInputs = with pkgs; [libclang];
  dontDubTest = true;

  meta = with lib; {
    description = "Directly include C headers in D source code";
    homepage = "https://github.com/atilaneves/dpp";
    license = licenses.boost;
    maintainers = with maintainers; [];
    mainProgram = "dpp";
    platforms = platforms.all;
  };
}
