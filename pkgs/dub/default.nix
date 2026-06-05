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
  ldc,
  dcompiler ? ldc,
  ...
}:
assert dcompiler != null;
let
  inherit (import ../../lib/build-status.nix { inherit lib; }) getBuildStatus;
  inherit (import ../../lib/dc.nix { inherit lib; }) getDCInfo;

  buildStatus = getBuildStatus "dub" version stdenv.system;

  hostDCInfo = getDCInfo dcompiler;
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
    dcompiler
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
    $dc ./build.d
    ./build
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
    platforms = [
      "x86_64-linux"
      "i686-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
