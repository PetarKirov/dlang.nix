{
  lib,
  pkgs,
  stdenv,
  fetchFromGitHub,
  dub,
  dmd,
}:
stdenv.mkDerivation rec {
  pname = "tsv-utils";
  version = "2.2.1";

  src = fetchFromGitHub {
    owner = "eBay";
    repo = "tsv-utils";
    rev = "v${version}";
    hash = "sha256-fFPU/SsicVNYJXdW6X+4GZwEx/mLYL2fd32TVB0ZKDs=";
  };

  nativeBuildInputs = with pkgs; [gnumake dub dmd];

  installPhase = ''
    mkdir -p $out/bin
    cp -r bin/* $out/bin
  '';

  meta = with lib; {
    description = "EBay's TSV Utilities: Command line tools for large, tabular data files. Filtering, statistics, sampling, joins and more";
    homepage = "https://github.com/eBay/tsv-utils";
    license = licenses.boost;
    maintainers = with maintainers; [];
    mainProgram = "tsv-utils";
    platforms = platforms.all;
  };
}
