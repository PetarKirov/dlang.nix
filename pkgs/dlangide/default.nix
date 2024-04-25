{
  lib,
  buildDubPackage,
  fetchFromGitHub,
  pkgs,
}:
buildDubPackage rec {
  pname = "dlangide";
  version = "0.8.19";

  src = fetchFromGitHub {
    owner = "buggins";
    repo = "dlangide";
    rev = "v${version}";
    hash = "sha256-DifB79pqeKIAz7CNdir2tGPg//vwcAOX2mKn2UcmDds=";
  };

  dubSelections = ./dub.selections.json;
  buildInputs = [pkgs.zlib pkgs.SDL2];

  meta = with lib; {
    description = "D language IDE based on DlangUI";
    homepage = "https://github.com/buggins/dlangide";
    license = licenses.boost;
    maintainers = with maintainers; [];
    mainProgram = "dlangide";
    platforms = platforms.all;
  };
}
