{
  lib,
  writeShellScriptBin,
  buildDubPackage,
  fetchFromGitHub,
}: let
  fakeGit = writeShellScriptBin "git" ''
    #!/bin/sh
    echo "fake-git: $@" >&2
    exit 0
  '';
in
  buildDubPackage rec {
    pname = "dubproxy";
    version = "1.1.3";

    src = fetchFromGitHub {
      owner = "symmetryinvestments";
      repo = "dubproxy";
      rev = "v${version}";
      hash = "sha256-KasJe6CzMQLKqrcJFkuGkexLUEQu8ZkUN8etdvo+uqk=";
      leaveDotGit = true;
    };

    dubSelections = ./dub.selections.json;
    dubBuildFlags = [
      "--config=cli"
    ];
    dontdubTest = true;
    nativeBuildInputs = [fakeGit];

    meta = with lib; {
      description = "A small library and cli to bypass code.dlang.org in a way transparent to dub";
      homepage = "https://github.com/symmetryinvestments/dubproxy";
      license = licenses.lgpl3Only;
      maintainers = with maintainers; [];
      mainProgram = "dubproxy";
      platforms = platforms.all;
    };
  }
