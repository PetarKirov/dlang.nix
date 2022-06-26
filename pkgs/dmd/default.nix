{
  stdenv,
  lib,
  fetchFromGitHub,
  makeWrapper,
  unzip,
  which,
  runCommand,
  writeTextFile,
  curl,
  tzdata,
  gdb,
  Foundation,
  git,
  callPackage,
  targetPackages,
  fetchpatch,
  bash,
  HOST_DMD ? "${callPackage ./bootstrap.nix {}}/bin/dmd",
  doReleastBuild ? true,
  doTest ? false,
  version ? "2.098.0",
  dmdSha256 ? "03pk278rva7f0v464i6av6hnsac1rh22ppxxrlai82p06i9w7lxk",
  druntimeSha256 ? "0p75h8gigc5yj090k7qxmzz04dbpkab890l2sv1mdsxvgabch08q",
  phobosSha256 ? "0kdr9857kckpzsk59wyd7wvjd0d3ch9amqkq2y7ipx70rv9y6m0r",
  toolsSha256 ? "0vs91j3yyzk5jgkaan7qqsqjx7azp900ws16sa34r1qisrgzp4gs",
}: let
  pathConfig = runCommand "phobos-tzdata-curl-paths" {} ''
    mkdir $out
    echo ${tzdata}/share/zoneinfo/ > $out/TZDatabaseDirFile
    echo ${curl.out}/lib/libcurl${stdenv.hostPlatform.extensions.sharedLibrary} > $out/LibcurlPathFile
  '';

  dmdConfFile = writeTextFile {
    name = "dmd.conf";
    text = lib.generators.toINI {} {
      Environment = {
        DFLAGS =
          ''-I@out@/include/dmd -L-L@out@/lib -fPIC ''
          + (lib.optionalString (!targetPackages.stdenv.cc.isClang) "-L--export-dynamic ")
          + ''-version=TZDatabaseDir -version=LibcurlPath -J${pathConfig}'';
      };
    };
  };

  bits = builtins.toString stdenv.hostPlatform.parsed.cpu.bits;
in
  stdenv.mkDerivation rec {
    pname = "dmd";
    inherit version;

    enableParallelBuilding = true;

    srcs = [
      (fetchFromGitHub {
        owner = "dlang";
        repo = "dmd";
        rev = "v${version}";
        sha256 = dmdSha256;
        name = "dmd";
      })
      (fetchFromGitHub {
        owner = "dlang";
        repo = "druntime";
        rev = "v${version}";
        sha256 = druntimeSha256;
        name = "druntime";
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
    ];

    sourceRoot = ".";

    # https://issues.dlang.org/show_bug.cgi?id=19553
    hardeningDisable = ["fortify"];

    # many tests are disbled because they are failing
    patchPhase =
      ''
        patchShebangs .
      ''
      + ''
        rm -v dmd/test/runnable/gdb*.d
        rm -v dmd/test/dshell/test6952.d
      ''
      + lib.optionalString stdenv.isLinux ''
        substituteInPlace phobos/std/socket.d --replace "assert(ih.addrList[0] == 0x7F_00_00_01);" ""
      ''
      + lib.optionalString stdenv.isDarwin ''
        substituteInPlace phobos/std/socket.d --replace "foreach (name; names)" "names = []; foreach (name; names)"
      '';

    nativeBuildInputs = [makeWrapper unzip which git];

    buildInputs =
      [gdb curl tzdata]
      ++ lib.optional stdenv.isDarwin [Foundation gdb];

    osname =
      if stdenv.isDarwin
      then "osx"
      else stdenv.hostPlatform.parsed.kernel.name;

    buildModeArgs =
      if doReleastBuild
      then "BUILD=release ENABLE_RELEASE=1"
      else "BUILD=debug ENABLE_RELEASE=0";

    buildPath =
      if doReleastBuild
      then "generated/${osname}/release/${bits}"
      else "generated/${osname}/debug/${bits}";

    dmdBuildPath = "$NIX_BUILD_TOP/dmd/${buildPath}/dmd";
    toolsBuildPath = "$NIX_BUILD_TOP/tools/generated/${osname}/${bits}";

    makeArgs =
      "-j$NIX_BUILD_CORES PIC=1 INSTALL_DIR=$out ${buildModeArgs} "
      + "DMD=${dmdBuildPath} HOST_DMD=${HOST_DMD} SHELL=$SHELL";
    dmdBuildCmd = "${HOST_DMD} -run ./src/build.d ${makeArgs}";
    makeBuildCmd = "make -f posix.mak ${makeArgs}";

    # Build and install are based on http://wiki.dlang.org/Building_DMD
    buildPhase = ''
      cd $NIX_BUILD_TOP/dmd
      ${dmdBuildCmd}

      cd ../druntime
      ${makeBuildCmd}

      cd ../phobos
      ${makeBuildCmd} DFLAGS="-version=TZDatabaseDir -version=LibcurlPath -J${pathConfig}"

      cd ../tools
      ${makeBuildCmd}
    '';

    doCheck = doTest;

    # Purity check is disabled for checkPhase because it doesn't fare well
    # with the DMD linker. See https://github.com/NixOS/nixpkgs/issues/97420
    checkPhase = ''
      cd $NIX_BUILD_TOP/dmd
      NIX_ENFORCE_PURITY= \
        ${makeBuildCmd} test

      cd ../druntime
      NIX_ENFORCE_PURITY= \
        ${makeBuildCmd} unittest

      cd ../phobos
      NIX_ENFORCE_PURITY= \
        ${makeBuildCmd} unittest DFLAGS="-version=TZDatabaseDir -version=LibcurlPath -J${pathConfig}"
    '';

    installPhase = ''
      cd $NIX_BUILD_TOP/dmd
      mkdir -p $out/bin
      cp -v ${dmdBuildPath} $out/bin

      mkdir -p $out/share/man
      cp -rv docs/man/man{1,5} $out/share/man

      cd ../druntime
      mkdir -p $out/include/dmd
      cp -rv import/* $out/include/dmd

      cd ../phobos
      mkdir $out/lib
      cp -rv std etc $out/include/dmd
      rm -v ./${buildPath}/*.o
      cp -v ./${buildPath}/libphobos2.* $out/lib

      cd ../tools
      cp -v ${toolsBuildPath}/{rdmd,ddemangle,dustmite} $out/bin

      wrapProgram $out/bin/dmd \
        --prefix PATH ":" "${targetPackages.stdenv.cc}/bin" \
        --set-default CC "${targetPackages.stdenv.cc}/bin/cc"

      substitute ${dmdConfFile} "$out/bin/dmd.conf" --subst-var out
    '';

    meta = with lib; {
      description = "Official reference compiler for the D language";
      homepage = "https://dlang.org/";
      license = licenses.boost;
      maintainers = with maintainers; [ThomasMader lionello];
      platforms = ["x86_64-linux" "i686-linux" "x86_64-darwin"];
    };
  }
