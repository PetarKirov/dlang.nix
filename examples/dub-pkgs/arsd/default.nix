{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "arsd";
  version = "unstable-2024-03-21";

  src = fetchFromGitHub {
    owner = "adamdruppe";
    repo = "arsd";
    rev = "01c7b280adf5120d77640f217ab9afaa5d76d21a";
    hash = "sha256-S4X+3BN53St14qktBbQQuWIwhvmEEjTrloM2yIQdsRs=";
  };

  dubSelections = ./dub.selections.json;

  meta = with lib; {
    description = "This is a collection of modules that I've released over the years. Most of them stand alone, or have just one or two dependencies in here, so you don't have to download this whole repo";
    homepage = "https://github.com/adamdruppe/arsd";
    # license = licenses.unfree; # FIXME: nix-init did not found a license
    maintainers = with maintainers; [];
    mainProgram = "arsd";
    platforms = platforms.all;
  };
}
