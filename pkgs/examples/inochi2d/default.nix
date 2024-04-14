{
  lib,
  buildDubPackage,
  fetchFromGitHub,
  pkgs,
}:
buildDubPackage rec {
  pname = "inochi2d";
  version = "0.8.3";

  src = fetchFromGitHub {
    owner = "Inochi2D";
    repo = "inochi2d";
    rev = "v${version}";
    hash = "sha256-yxxC1sRzfEETgy1hSOe4S5ex2b118oxzbWdaT7DZY6c=";
  };

  nativeBuildInputs = [pkgs.git];

  dubSelections = ./dub.selections.json;

  meta = with lib; {
    description = "Inochi2D reference implementation aimed at rendering 2D puppets that can be animated in real-time (using eg. facial capture";
    homepage = "https://github.com/Inochi2D/inochi2d";
    license = licenses.bsd2;
    maintainers = with maintainers; [];
    mainProgram = "inochi2d";
    platforms = platforms.all;
  };
}
