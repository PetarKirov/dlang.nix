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
  dCompiler,
  ...
}:
let
  inherit (import ../../lib/build-status.nix { inherit lib; }) getBuildStatus;
  inherit (import ../../lib/dc.nix { inherit lib; }) getDCInfo;

  buildStatus = getBuildStatus "dub" version stdenv.system;

  # Offer this package only on the systems where the build matrix says it
  # builds. The pre-1.20 releases pin vintage `ldc-binary` hosts that are only
  # published for x86_64, so without this they would be surfaced on (and fail to
  # evaluate on) systems such as aarch64-darwin where no such bootstrap binary
  # exists.
  buildPlatforms = lib.attrNames (
    lib.filterAttrs (_system: status: status.build) (
      (import ./build-status.nix { inherit lib; }).${version} or { }
    )
  );

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
    patchShebangs .


    # Can be removed with https://github.com/dlang/dub/pull/1368
    if [ -f test/fetchzip.sh ]; then
      substituteInPlace test/fetchzip.sh \
          --replace "dub remove" "\"${dubvar}\" remove"
    fi

    # Fix a missing comma in dub 1.0.0 that causes implicit string concatenation error
    ${lib.optionalString (lib.versionOlder version "1.1.0") ''
      substituteInPlace source/dub/commandline.d \
          --replace '"This command will convert between JSON and SDLang formatted package recipe files."' '"This command will convert between JSON and SDLang formatted package recipe files.",'
    ''}
  '';

  nativeBuildInputs = [
    dCompiler
    libevent
    rsync
  ];
  buildInputs = [ curl ];

  buildPhase = ''
    for dc_ in dmd ldmd2 gdmd; do
      echo "... check for D compiler $dc_ ..."
      dc=$(type -P $dc_ || echo "")
      if [ ! "$dc" == "" ]; then
        break
      fi
    done
    if [ "$dc" == "" ]; then
      exit "Error: could not find D compiler"
    fi
    echo "$dc_ found and used as D compiler to build $pname"

    if [ -f ./build.d ]; then
      $dc ./build.d
      ./build
    elif [ -f ./build.sh ]; then
      export DMD=$dc
      export GITVER=v${version}
      ./build.sh ${lib.optionalString stdenv.hostPlatform.isLinux "-L-no-pie"}
    else
      echo "Error: no build script found"
      exit 1
    fi
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

  meta = with lib; {
    description = "Package and build manager for D applications and libraries";
    homepage = "https://code.dlang.org/";
    license = licenses.mit;
    maintainers = with maintainers; [ ThomasMader ];
    platforms = buildPlatforms;
  };
}
