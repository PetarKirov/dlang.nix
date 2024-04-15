{
  lib,
  pkgs,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "dcd";
  version = "0.15.2";

  src = fetchFromGitHub {
    owner = "dlang-community";
    repo = "DCD";
    rev = "v${version}";
    hash = "sha256-dJ4Ql3P9kPQhQ3ZrNcTAEB5JHSslYn2BN8uqq6vGetY=";
  };

  dontDubInstall = true;
  InstallPhase = ''
    mkdir -p $out/bin
    cp -r dcd-{client,server} $out/bin
  '';

  meta = with lib; {
    description = "The D Completion Daemon is an auto-complete program for the D programming language ";
    homepage = "https://github.com/dlang-community/DCD";
    license = licenses.gpl3;
    maintainers = with maintainers; [];
    mainProgram = "dcd-client";
    platforms = platforms.all;
  };
}
