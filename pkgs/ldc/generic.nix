{
  version,
  sha256,
}: {
  lib,
  stdenv,
  writeTextFile,
  fetchurl,
  cmake,
  ninja,
  llvmPackages_12,
  curl,
  tzdata,
  libconfig,
  lit,
  gdb,
  unzip,
  darwin,
  bash,
  pkgconfig,
  callPackage,
  makeWrapper,
  runCommand,
  targetPackages,
  ldcBootstrap ? callPackage ./bootstrap.nix {},
}: let
  pathConfig = runCommand "phobos-tzdata-curl-paths" {} ''
    mkdir $out
    echo ${tzdata}/share/zoneinfo/ > $out/TZDatabaseDirFile
    echo ${curl.out}/lib/libcurl${stdenv.hostPlatform.extensions.sharedLibrary} > $out/LibcurlPathFile
  '';

  ldcConfFile = writeTextFile {
    name = "ldc2.conf";
    text = ''
      // Based on https://github.com/ldc-developers/ldc/blob/v1.28.0/ldc2.conf.in
      default:
      {
        switches = [
          "-defaultlib=phobos2-ldc,druntime-ldc",
          "-link-defaultlib-shared",
          "-d-version=TZDatabaseDir",
          "-d-version=LibcurlPath",
        ];
        post-switches = [
          "-I=@out@/include/d",
          "-J=${pathConfig}",
        ];
        lib-dirs = [
          "@out@/lib",
        ];
        rpath = "@out@/lib";
      };

      "^wasm(32|64)-":
      {
        switches = [
          "-defaultlib=",
          "-L--export-dynamic",
        ];
        lib-dirs = [];
      };'';
  };
in
  stdenv.mkDerivation rec {
    pname = "ldc";
    inherit version;

    src = fetchurl {
      url = "https://github.com/ldc-developers/ldc/releases/download/v${version}/ldc-${version}-src.tar.gz";
      inherit sha256;
    };

    # https://issues.dlang.org/show_bug.cgi?id=19553
    hardeningDisable = ["fortify"];

    postUnpack =
      ''
        patchShebangs .
      ''
      + ''
        rm ldc-${version}-src/tests/d2/dmd-testsuite/fail_compilation/mixin_gc.d
        rm ldc-${version}-src/tests/d2/dmd-testsuite/runnable/xtest46_gc.d
        rm ldc-${version}-src/tests/d2/dmd-testsuite/runnable/testptrref_gc.d

        # test depends on current year
        rm ldc-${version}-src/tests/d2/dmd-testsuite/compilable/ddocYear.d
      ''
      + lib.optionalString stdenv.hostPlatform.isDarwin ''
        # https://github.com/NixOS/nixpkgs/issues/34817
        rm -r ldc-${version}-src/tests/plugins/addFuncEntryCall
      '';

    postPatch =
      ''
        # Setting SHELL=$SHELL when dmd testsuite is run doesn't work on Linux somehow
        substituteInPlace tests/d2/dmd-testsuite/Makefile --replace "SHELL=/bin/bash" "SHELL=${bash}/bin/bash"
      ''
      + lib.optionalString stdenv.hostPlatform.isLinux ''
        substituteInPlace runtime/phobos/std/socket.d --replace "assert(ih.addrList[0] == 0x7F_00_00_01);" ""
      ''
      + lib.optionalString stdenv.hostPlatform.isDarwin ''
        substituteInPlace runtime/phobos/std/socket.d --replace "foreach (name; names)" "names = []; foreach (name; names)"
      '';

    nativeBuildInputs =
      [
        cmake
        ldcBootstrap
        lit
        lit.python
        llvmPackages_12.llvm.dev
        makeWrapper
        ninja
        unzip
        pkgconfig
      ]
      ++ lib.optional stdenv.hostPlatform.isDarwin darwin.apple_sdk.frameworks.Foundation
      # https://github.com/NixOS/nixpkgs/pull/36378#issuecomment-385034818
      ++ lib.optional (!stdenv.hostPlatform.isDarwin) gdb;

    buildInputs = [curl tzdata];

    cmakeFlags = [
      "-DD_FLAGS=-d-version=TZDatabaseDir;-d-version=LibcurlPath;-J${pathConfig}"
      "-DCMAKE_BUILD_TYPE=Release"
    ];

    fixNames = lib.optionalString stdenv.hostPlatform.isDarwin ''
      fixDarwinDylibNames() {
        local flags=()

        for fn in "$@"; do
          flags+=(-change "$(basename "$fn")" "$fn")
        done

        for fn in "$@"; do
          if [ -L "$fn" ]; then continue; fi
          echo "$fn: fixing dylib"
          install_name_tool -id "$fn" "''${flags[@]}" "$fn"
        done
      }

      fixDarwinDylibNames $(find "$(pwd)/lib" -name "*.dylib")
      export DYLD_LIBRARY_PATH=$(pwd)/lib
    '';

    # https://github.com/ldc-developers/ldc/issues/2497#issuecomment-459633746
    additionalExceptions =
      lib.optionalString stdenv.hostPlatform.isDarwin
      "|druntime-test-shared";

    checkPhase = ''
      # Build default lib test runners
      ninja -j$NIX_BUILD_CORES all-test-runners

      ${fixNames}

      # Run dmd testsuite
      export DMD_TESTSUITE_MAKE_ARGS="-j$NIX_BUILD_CORES DMD=$DMD"
      ctest -V -R "dmd-testsuite"

      # Build and run LDC D unittests.
      ctest --output-on-failure -R "ldc2-unittest"

      # Run LIT testsuite.
      ctest -V -R "lit-tests"

      # Run default lib unittests
      ctest -j$NIX_BUILD_CORES --output-on-failure -E "ldc2-unittest|lit-tests|dmd-testsuite${additionalExceptions}"
    '';

    postInstall = ''
      substitute ${ldcConfFile} "$out/etc/ldc2.conf" --subst-var out

      wrapProgram $out/bin/ldc2 \
          --prefix PATH ":" "${targetPackages.stdenv.cc}/bin" \
          --set-default CC "${targetPackages.stdenv.cc}/bin/cc"
    '';

    meta = with lib; {
      description = "The LLVM-based D compiler";
      homepage = "https://github.com/ldc-developers/ldc";
      # from https://github.com/ldc-developers/ldc/blob/master/LICENSE
      license = with licenses; [bsd3 boost mit ncsa gpl2Plus];
      maintainers = with maintainers; [ThomasMader lionello];
      platforms = ["x86_64-linux" "i686-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    };
  }
