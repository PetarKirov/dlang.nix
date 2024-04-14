{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "xlsxreader";
  version = "3.1.0";

  src = fetchFromGitHub {
    owner = "symmetryinvestments";
    repo = "xlsxreader";
    rev = "v${version}";
    hash = "sha256-opsYhxy+z2eESRpdVR76af1Np3t4E6BCq48mjnafx24=";
  };

  dubSelections = ./dub.selections.json;

  meta = with lib; {
    description = "A KISS xlsx reader";
    homepage = "https://github.com/symmetryinvestments/xlsxreader";
    # license = licenses.unfree; # FIXME: nix-init did not found a license
    maintainers = with maintainers; [];
    mainProgram = "xlsxreader";
    platforms = platforms.all;
  };
}
