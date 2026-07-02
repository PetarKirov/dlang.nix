{
  lib,
  buildDubPackage,
}:
# The repo's `dlang-nix-fetcher` D tool: prefetches DMD/LDC/dub releases and,
# via the `ci` subcommand, packs the CI build matrix. Packaged so the
# matrix-generation step (`scripts/ci-matrix.sh`) can call `dlang-nix-fetcher ci
# plan-matrix` from the `.#ci` dev shell without a `dub build` on the hot path.
# Built with the nixpkgs LDC (not the repo's own, to avoid a build cycle).
buildDubPackage {
  pname = "dlang-nix-fetcher";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../dub.sdl
      ../../dub.selections.json
      ../../src
    ];
  };

  dubLock = ./dub-lock.json;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/dlang-nix-fetcher "$out/bin/dlang-nix-fetcher"
    runHook postInstall
  '';

  meta = {
    description = "Fetches DMD/LDC/dub releases and packs the dlang.nix CI build matrix";
    mainProgram = "dlang-nix-fetcher";
  };
}
