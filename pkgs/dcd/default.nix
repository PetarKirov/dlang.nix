{
  lib,
  pkgs,
  buildDubPackage,
  fetchFromGitHub,
  writeShellScriptBin,
}: let
  fakeGit = writeShellScriptBin "git" ''
    #!/bin/sh
    echo "fake-git: $@" >&2
    exit 0
  '';
in
  buildDubPackage rec {
    pname = "dcd";
    version = "0.15.2";

    src = fetchFromGitHub {
      owner = "dlang-community";
      repo = "DCD";
      rev = "v${version}";
      hash = "sha256-3OWTnvDDiUnF8mVM98uUqYqLAJwI4AH+CN5C8WCPDOs=";
      leaveDotGit = true;
      fetchSubmodules = true;
    };

    nativeBuildInputs = with pkgs; [gnumake fakeGit];

    dontDubInstall = true;
    dontDubBuild = true;
    preBuild = ''
      sed -i 's/git describe --tags/echo v${version}/' makefile
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp bin/dcd-{client,server} $out/bin
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
