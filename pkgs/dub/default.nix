{
  version,
  dubSha256,
  rev ? "v${version}",
}:
{
  lib,
  stdenv,
  fetchFromGitHub,
  curl,
  libevent,
  rsync,
  removeReferencesTo,
  dCompiler,
  ...
}:
let
  inherit (import ../../lib/build-status.nix { inherit lib; }) getBuildStatus;
  inherit (import ../../lib/dc.nix { inherit lib; }) getDCInfo;

  buildStatus = getBuildStatus "dub" version stdenv.system;

  hostDCInfo = getDCInfo dCompiler;
in
stdenv.mkDerivation rec {
  pname = "dub";
  inherit version;

  passthru = {
    inherit buildStatus;
  };

  enableParallelBuilding = true;

  src = fetchFromGitHub {
    owner = "dlang";
    repo = "dub";
    inherit rev;
    sha256 = dubSha256;
  };

  dubvar = "\\$DUB";
  postPatch = ''
    patchShebangs test


    # Can be removed with https://github.com/dlang/dub/pull/1368
    substituteInPlace test/fetchzip.sh \
        --replace "dub remove" "\"${dubvar}\" remove"
  '';

  nativeBuildInputs = [
    dCompiler
    libevent
    rsync
    removeReferencesTo
  ];
  buildInputs = [ curl ];

  buildPhase =
    let
      # Use static linking when building with LDC to keep LDC+LLVM out of the closure
      dflags = lib.optionalString (hostDCInfo.name == "ldc") "DFLAGS='-link-defaultlib-shared=false'";
    in
    ''
      runHook preBuild

      echo "Building $pname with ${hostDCInfo.dmdWrapper}"
      ${hostDCInfo.dmdWrapper} ./build.d
      ${dflags} ./build

      runHook postBuild
    '';

  doCheck = buildStatus.check;

  checkPhase = ''
    export DUB=$NIX_BUILD_TOP/source/bin/dub
    export PATH=$PATH:$NIX_BUILD_TOP/source/bin/
    export DC=${hostDCInfo.dmdWrapper}
    echo "DC out --> $DC"
    export HOME=$TMP

    # Skipped tests
    ${lib.concatMapStringsSep "\n" (test: "rm -rf test/${test}") buildStatus.skippedTests}

    ./test/run-unittest.sh
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp bin/dub $out/bin
  '';

  # The static link leaves LDC's store path in the binary as a dead string
  # (default-lib path / debug info); scrub it so it isn't a runtime dependency.
  preFixup = lib.optionalString stdenv.hostPlatform.isElf ''
    remove-references-to -t ${dCompiler} $out/bin/dub
  '';

  # Fail if the LDC+LLVM toolchain leaks into the runtime closure.
  disallowedReferences = lib.optionals stdenv.hostPlatform.isElf [ dCompiler ];

  meta = with lib; {
    description = "Package and build manager for D applications and libraries";
    homepage = "https://code.dlang.org/";
    license = licenses.mit;
    maintainers = with maintainers; [ ThomasMader ];
    platforms = [
      "x86_64-linux"
      "i686-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "dub";
  };
}
