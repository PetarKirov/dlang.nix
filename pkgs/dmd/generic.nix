{
  version,
  dmdSha256,
  # only needed before version 2.101.0
  druntimeSha256 ? "",
  phobosSha256,
  toolsSha256,
  enableAsserts ? false,
  enableCoverage ? false,
  enableDebug ? false,
  enableLTO ? false,
  enableProfile ? false,
  enableRelease ? true,
  enableUnittest ? false,
}:
{
  stdenv,
  lib,
  fetchFromGitHub,
  makeWrapper,
  which,
  runCommand,
  writeTextFile,
  curl,
  tzdata,
  gdb,
  gcc11,
  Foundation,
  targetPackages,
  fetchpatch,
  bash,
  installShellFiles,
  git,
  unzip,
  hostDCompiler,
}:
let
  inherit (import ../../lib/build-status.nix { inherit lib; }) getBuildStatus;
  inherit (import ../../lib/version-utils.nix { inherit lib; }) versionBetween;
  inherit (import ../../lib/dc.nix { inherit lib; }) getDCInfo;

  hostDCInfo = getDCInfo hostDCompiler;

  buildStatus = getBuildStatus "dmd" version stdenv.system;

  pathConfig = runCommand "phobos-tzdata-curl-paths" { } ''
    mkdir $out
    echo '${tzdata}/share/zoneinfo/' > $out/TZDatabaseDirFile
    echo '${lib.getLib curl}/lib/libcurl${stdenv.hostPlatform.extensions.sharedLibrary}' > $out/LibcurlPathFile
  '';

  phobosDflags = "-version=TZDatabaseDir -version=LibcurlPath -J${pathConfig}";

  dmdConfFile = writeTextFile {
    name = "dmd.conf";
    text = lib.generators.toINI { } {
      Environment = {
        DFLAGS = builtins.concatStringsSep " " [
          "-I@out@/include/dmd"
          "-L-L@out@/lib"
          "-fPIC"
          (lib.optionalString (!targetPackages.stdenv.cc.isClang) "-L--export-dynamic")
          phobosDflags
        ];
      };
    };
  };

  bits = builtins.toString stdenv.hostPlatform.parsed.cpu.bits;
  os = if stdenv.isDarwin then "osx" else stdenv.hostPlatform.parsed.kernel.name;

  buildMode = if enableRelease then "release" else "debug";

  buildPath = "generated/${os}/${buildMode}/${bits}";
  druntimeRepo = lib.versionOlder version "2.101.0";
  dmdPrefix = if druntimeRepo then "dmd" else "dmd/compiler";

  druntimePrefix = if druntimeRepo then "druntime" else "dmd/druntime";

  commonBuildFlags =
    { forMake }:
    [
      "SHELL=${bash}/bin/bash"
      "DMD=$(NIX_BUILD_TOP)/dmd/${buildPath}/dmd"
      "CC=${if stdenv.isDarwin then stdenv.cc else gcc11}/bin/cc"
      "HOST_DMD=${hostDCInfo.dmdWrapper}"
      "PIC=1"
      "BUILD=${buildMode}"
    ]
    ++ lib.optional forMake "-fposix.mak"
    # There is an "ifdef ENABLE_COVERAGE" rule in Phobos posix.max causing
    # coverage to be enabled even if it's set to 0. For consistency we leave
    # any false values unset.
    ++ lib.optional enableRelease "ENABLE_RELEASE=1"
    ++ lib.optional enableAsserts "ENABLE_ASSERTS=1"
    ++ lib.optional enableDebug "ENABLE_DEBUG=1"
    ++ lib.optional enableLTO "ENABLE_LTO=1"
    ++ lib.optional enableProfile "ENABLE_PROFILE=1"
    ++ lib.optional enableUnittest "ENABLE_UNITTEST=1"
    ++ lib.optional enableCoverage "ENABLE_COVERAGE=1";
in
stdenv.mkDerivation rec {
  pname = "dmd";
  inherit version;

  passthru = {
    inherit buildStatus;
  };

  enableParallelBuilding = true;

  srcs =
    [
      (fetchFromGitHub {
        owner = "dlang";
        repo = "dmd";
        rev = "v${version}";
        sha256 = dmdSha256;
        name = "dmd";
      })
      (fetchFromGitHub {
        owner = "dlang";
        repo = "phobos";
        rev = "v${version}";
        sha256 = phobosSha256;
        name = "phobos";
      })
      (fetchFromGitHub {
        owner = "dlang";
        repo = "tools";
        rev = "v${version}";
        sha256 = toolsSha256;
        name = "tools";
      })
    ]
    ++ lib.optionals druntimeRepo [
      (fetchFromGitHub {
        owner = "dlang";
        repo = "druntime";
        rev = "v${version}";
        sha256 = druntimeSha256;
        name = "druntime";
      })
    ];

  sourceRoot = ".";

  # https://issues.dlang.org/show_bug.cgi?id=19553
  hardeningDisable = [ "fortify" ];

  patches =
    lib.optionals (lib.versionOlder version "2.088.0") [
      # Migrates D1-style operator overloads in DMD source, to allow building with
      # a newer DMD
      (fetchpatch {
        url = "https://github.com/dlang/dmd/commit/c4d33e5eb46c123761ac501e8c52f33850483a8a.patch";
        stripLen = 1;
        extraPrefix = "dmd/";
        sha256 = "sha256-N21mAPfaTo+zGCip4njejasraV5IsWVqlGR5eOdFZZE=";
      })
    ]
    ++ lib.optionals (lib.versionOlder version "2.091.0") [
      # Patches deprecated printf formats in dmd backend
      (fetchpatch {
        url = "https://github.com/dlang/dmd/commit/efe6d473c30c07074461f3de0b7a8ba1343c5429.patch";
        stripLen = 1;
        extraPrefix = "dmd/";
        sha256 = "sha256-DdAIHK42q4vyVJsuTN0nRZAAjWXRBZHY8oUidW4pMwI=";
      })
    ]
    ++ lib.optionals (lib.versionOlder version "2.096.1") [
      # Stop using feature deprecated from 2.097.0 on, link:
      # https://dlang.org/changelog/2.097.0.html#fqn-bypass-deprecation
      (fetchpatch {
        url = "https://github.com/dlang/dmd/commit/5198eedf6ef4e113773c15eff42de195be438fa1.patch";
        stripLen = 1;
        extraPrefix = "dmd/";
        sha256 = "sha256-4Bd3YD14jzMelVvR2t738Dtrf7xMlWJM6AdsB34wKyM=";
      })
    ]
    ++ lib.optionals (lib.versionOlder version "2.092.2") [
      # Fixes C++ tests that compiled on older C++ but not on the current one
      (fetchpatch {
        url = "https://github.com/dlang/druntime/commit/438990def7e377ca1f87b6d28246673bb38022ab.patch";
        stripLen = 1;
        extraPrefix = "druntime/";
        sha256 = "sha256-/pPKK7ZK9E/mBrxm2MZyBNhYExE8p9jz8JqBdZSE6uY=";
      })
    ]
    ++ lib.optionals (versionBetween "2.092.0" "2.101.0" version) [
      # `src/dmd/backend/cg.d` and `src/dmd/backend/var.d` contained arrays defined as
      # result from IIFE at CT. These function expressions were inside a
      # `extern (C++):` block, however they were returning static arrays, which
      # is not allowed in C++. This patch marks them as `extern (D)`, to avoid
      # this issue.
      # See: https://github.com/dlang/dmd/pull/14127
      (fetchpatch {
        url = "https://github.com/dlang/dmd/commit/c4cea697e8658f103a69967587e75dd130506304.patch";
        stripLen = 1;
        extraPrefix = "dmd/";
        sha256 = "sha256-JO52sxliPFjCe4qyo/eyWhDTg1x5bh1+7gPj1SYXIh8=";
      })
    ]
    ++ lib.optionals (versionBetween "2.102.2" "2.104.0" version) [
      (fetchpatch {
        # Fix for: https://issues.dlang.org/show_bug.cgi?id=23846
        # Implemented in: https://github.com/dlang/dmd/pull/15139
        url = "https://github.com/dlang/dmd/commit/deaf1b81986c57d31a1b1163301ca4d157505220.patch";
        stripLen = 1;
        extraPrefix = "dmd/";
        sha256 = "sha256-xgaIraFH3ZfIn99ms148MP7cKV63JgU90yEYq21noRw=";
      })
    ];

  postPatch =
    # Older compilers use -dip25 in their build flags, but if the build
    # compiler is 2.092 or newer it doesn't need it anymore, and from
    # 2.103 on using the flag is a deprecation error.
    lib.optionalString (lib.versionAtLeast hostDCInfo.frontendVersion "2.092.0") ''
      substituteInPlace ${dmdPrefix}/src/build.d --replace '"-dip25"' ""
    ''
    + lib.optionalString (versionBetween "2.092.0" "2.103.0" version) ''
      substituteInPlace ${dmdPrefix}/src/build.d --replace '"-w", "-de",' ""
    ''
    + ''
      patchShebangs ${dmdPrefix}/test/{runnable,fail_compilation,compilable,tools}{,/extra-files}/*.sh

      # Grep'd string changed with gdb 12
      #   https://issues.dlang.org/show_bug.cgi?id=23198
      substituteInPlace ${druntimePrefix}/test/exceptions/Makefile \
        --replace 'in D main (' 'in _Dmain ('

      # We're using gnused on all platforms
      substituteInPlace ${druntimePrefix}/test/coverage/Makefile \
        --replace 'freebsd osx' 'none'
    ''
    + lib.optionalString (lib.versionAtLeast version "2.092.2") ''
      substituteInPlace ${dmdPrefix}/test/dshell/test6952.d --replace "/usr/bin/env bash" "${bash}/bin/bash"
    ''
    # This test causes a linking failure before
    # https://github.com/dlang/dmd/commit/cab51f946a8b2d3f0fcb856cf6c52a18a6779930
    + lib.optionalString stdenv.isLinux ''
      substituteInPlace phobos/std/socket.d --replace "assert(ih.addrList[0] == 0x7F_00_00_01);" ""
    ''
    + lib.optionalString stdenv.isDarwin ''
      substituteInPlace phobos/std/socket.d --replace "foreach (name; names)" "names = []; foreach (name; names)"
    '';

  nativeBuildInputs = [
    makeWrapper
    which
    installShellFiles
  ] ++ lib.optional (lib.versionOlder version "2.088.0") git;

  buildInputs = [
    curl
    tzdata
  ] ++ lib.optional stdenv.isDarwin Foundation;

  nativeCheckInputs = [ gdb ] ++ lib.optional (lib.versionOlder version "2.089.0") unzip;

  dontConfigure = true;

  buildFlags = commonBuildFlags { forMake = true; };

  # Build and install are based on http://wiki.dlang.org/Building_DMD
  buildPhase = ''
    runHook preBuild

    export buildJobs=$NIX_BUILD_CORES
    if [ -z $enableParallelBuilding ]; then
      buildJobs=1
    fi
    export MAKEFLAGS="-j$buildJobs"

    make -C dmd $buildFlags
    ${lib.optionalString druntimeRepo "make -C druntime $buildFlags"}
    make -C phobos $buildFlags DFLAGS="${phobosDflags}"
    make -C tools $buildFlags

    runHook postBuild
  '';

  doCheck = buildStatus.check;

  checkInputs = lib.optional stdenv.isDarwin Foundation;

  checkFlagsMake = commonBuildFlags { forMake = true; } ++ [ "N=$(checkJobs)" ];
  checkFlagsRunD = commonBuildFlags { forMake = false; };

  # many tests are disbled because they are failing
  # NOTE: Purity check is disabled for checkPhase because it doesn't fare well
  # with the DMD linker. See https://github.com/NixOS/nixpkgs/issues/97420
  checkPhase = ''
    runHook preCheck
    ${lib.optionalString (buildStatus.skippedTests != [ ]) (
      lib.concatMapStringsSep "\n" (test: ''rm -v ${test}'') buildStatus.skippedTests
    )}
    export checkJobs=$NIX_BUILD_CORES
    if [ -z $enableParallelChecking ]; then
      checkJobs=1
    fi

    export MAKEFLAGS="-j$checkJobs"

    # This will also test DRuntime for versions without
    # a separate DRuntime repo
    (NIX_ENFORCE_PURITY= \
      cd ${dmdPrefix}/test && env $checkFlagsRunD ${hostDCompiler + /bin/rdmd} run.d -j $checkJobs all)

    ${lib.optionalString druntimeRepo ''
      NIX_ENFORCE_PURITY= \
        make -C druntime unittest $checkFlagsMake
    ''}

    NIX_ENFORCE_PURITY= \
      make -C phobos unittest $checkFlagsMake DFLAGS="${phobosDflags}"

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 dmd/${buildPath}/dmd $out/bin/dmd

    installManPage dmd/docs/man/man*/*

    mkdir -p $out/include/dmd
    cp -r {${druntimePrefix}/import/*,phobos/{std,etc}} $out/include/dmd/

    mkdir $out/lib
    cp phobos/${buildPath}/libphobos2.* $out/lib/

    wrapProgram $out/bin/dmd \
      --prefix PATH ":" "${targetPackages.stdenv.cc}/bin" \
      --set-default CC "${targetPackages.stdenv.cc}/bin/cc"

    substitute ${dmdConfFile} "$out/bin/dmd.conf" --subst-var out

    for tool in rdmd ddemangle dustmite; do
      install -Dm755 tools/generated/${os}/${bits}/$tool $out/bin/$tool
    done

    runHook postInstall
  '';

  meta = with lib; {
    description = "Official reference compiler for the D language";
    homepage = "https://dlang.org/";
    license = licenses.boost;
    maintainers = with maintainers; [
      ThomasMader
      lionello
      dukc
    ];
    platforms = [
      "x86_64-linux"
      "i686-linux"
      "x86_64-darwin"
    ];
  };
}
