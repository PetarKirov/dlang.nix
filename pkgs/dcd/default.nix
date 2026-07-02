{
  version,
  srcSha256,
  dubLock,
  rev ? "v${version}",
}:
{
  lib,
  stdenv,
  buildDubPackage,
  fetchFromGitHub,
  git,
  writeShellScriptBin,
}:
let
  buildStatus =
    (import ../../lib/build-status.nix { inherit lib; }).getBuildStatus "dcd" version
      stdenv.system;

  # Older tags invoke `rdmd dubhash.d` in their preBuildCommands (newer ones use
  # `"$DC" -run`). LDC ships `ldmd2` but not `rdmd`, so provide a shim that
  # forwards to it; harmless for tags that never call rdmd.
  rdmd = writeShellScriptBin "rdmd" ''exec ldmd2 -run "$@"'';
in
buildDubPackage {
  pname = "dcd";
  inherit version;

  passthru = {
    inherit buildStatus;
  };

  src = fetchFromGitHub {
    owner = "dlang-community";
    repo = "DCD";
    inherit rev;
    sha256 = srcSha256;
  };

  inherit dubLock;

  # DCD's `common` subpackage runs `$DC -run dubhash.d`, which stamps the
  # version from `git describe --tags`. The source archive carries no `.git`,
  # so init a throwaway repo tagged with the exact version.
  nativeBuildInputs = [
    git
    rdmd
  ];
  preBuild = ''
    export HOME=$TMPDIR
    git init -q
    git -c user.email=nix@build -c user.name=nix add -A
    git -c user.email=nix@build -c user.name=nix commit -qm build
    git tag "v${version}"
  '';

  # DCD ships three dub configurations (library/client/server) and the first
  # (library) is the default. Build the server via the hook, then the client.
  dubBuildFlags = [ "--config=server" ];
  postBuild = ''
    dub build --skip-registry=all --build="''${dubBuildType:-release}" \
      --config=client "''${dubFlags[@]}"
  '';

  doCheck = buildStatus.check;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/dcd-server bin/dcd-client -t $out/bin
    runHook postInstall
  '';

  meta = {
    description = "Auto-complete program (the D Completion Daemon) for the D programming language";
    homepage = "https://github.com/dlang-community/DCD";
    license = lib.licenses.gpl3Only;
    mainProgram = "dcd-server";
  };
}
