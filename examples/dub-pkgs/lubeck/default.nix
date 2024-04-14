{
  lib,
  pkgs,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "lubeck";
  version = "1.5.1";

  src = fetchFromGitHub {
    owner = "kaleidicassociates";
    repo = "lubeck";
    rev = "v${version}";
    hash = "sha256-KwWwOgvaInKyULk5D3lHp51ITdDYM4P33gJR+XU9Jwc=";
  };

  dubSelections = ./dub.selections.json;
  dontDubTest = true;
  buildInputs = with pkgs; [openblas];

  meta = with lib; {
    description = "High level linear algebra library for Dlang";
    homepage = "https://github.com/kaleidicassociates/lubeck";
    license = licenses.boost;
    maintainers = with maintainers; [];
    mainProgram = "lubeck";
    platforms = platforms.all;
  };
}
