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
    (import ../../lib/build-status.nix { inherit lib; }).getBuildStatus "dscanner" version
      stdenv.system;

  # Older tags invoke `rdmd dubhash.d` in their preBuildCommands (newer ones use
  # `"$DC" -run`). LDC ships `ldmd2` but not `rdmd`, so provide a shim that
  # forwards to it; harmless for tags that never call rdmd.
  rdmd = writeShellScriptBin "rdmd" ''exec ldmd2 -run "$@"'';
in
buildDubPackage {
  pname = "dscanner";
  inherit version;

  passthru = {
    inherit buildStatus;
  };

  src = fetchFromGitHub {
    owner = "dlang-community";
    repo = "D-Scanner";
    inherit rev;
    sha256 = srcSha256;
  };

  inherit dubLock;

  # Newer tags run `$DC -run dubhash.d`, which stamps the version from
  # `git describe --tags`. The source archive carries no `.git`, so init a
  # throwaway repo tagged with the exact version instead of patching each tag.
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

  doCheck = buildStatus.check;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/dscanner -t $out/bin
    runHook postInstall
  '';

  meta = {
    description = "Swiss-army knife for D source code";
    homepage = "https://github.com/dlang-community/D-Scanner";
    license = lib.licenses.boost;
    mainProgram = "dscanner";
  };
}
