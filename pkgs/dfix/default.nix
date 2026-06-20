{
  version,
  srcSha256,
  rev ? "v${version}",
}:
{
  lib,
  stdenv,
  buildDubPackage,
  fetchFromGitHub,
}:
let
  buildStatus =
    (import ../../lib/build-status.nix { inherit lib; }).getBuildStatus "dfix" version
      stdenv.system;
in
buildDubPackage {
  pname = "dfix";
  inherit version;

  passthru = {
    inherit buildStatus;
  };

  src = fetchFromGitHub {
    owner = "dlang-community";
    repo = "dfix";
    inherit rev;
    sha256 = srcSha256;
  };

  dubLock = ./locks/${version}.json;

  doCheck = buildStatus.check;

  # dfix has no `targetPath`, so the executable lands in the package root.
  installPhase = ''
    runHook preInstall
    install -Dm755 dfix -t $out/bin
    runHook postInstall
  '';

  meta = {
    description = "Tool for automatically upgrading D source code";
    homepage = "https://github.com/dlang-community/dfix";
    license = lib.licenses.boost;
    mainProgram = "dfix";
  };
}
