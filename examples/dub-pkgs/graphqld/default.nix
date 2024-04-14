{
  lib,
  buildDubPackage,
  fetchFromGitHub,
  pkgs,
}:
buildDubPackage rec {
  pname = "graphqld";
  version = "5.1.5";

  src = fetchFromGitHub {
    owner = "burner";
    repo = "graphqld";
    rev = "v${version}";
    hash = "sha256-X4Kv1ORNJba0c9w/yM6Wz1cfrD+vTjCNkobzq+rV12E=";
  };

  dubSelections = ./dub.selections.json;
  buildInputs = with pkgs; [openssl];

  meta = with lib; {
    description = "A vibe.d library to handle the GraphQL Protocol written in the D Programming Language";
    homepage = "https://github.com/burner/graphqld";
    license = licenses.lgpl3Only;
    maintainers = with maintainers; [];
    mainProgram = "graphqld";
    platforms = platforms.all;
  };
}
