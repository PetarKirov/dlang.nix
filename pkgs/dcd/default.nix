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
      # NOTE: do not set `leaveDotGit` here. It makes this fixed-output
      # derivation non-reproducible (the packed `.git` content depends on the
      # git-server's behaviour), so the pinned hash drifts and breaks the build.
      # The build does not need `.git`: it stubs `git` (fakeGit) and seds out
      # `git describe --tags` in preBuild.
      hash = "sha256-c5PAUjS2+DvY1QfI+whu0bqFQl0wDUzUUtfHjRFoieA=";
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
