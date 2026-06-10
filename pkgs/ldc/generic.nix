{ version, sha256 }:
{
  lib,
  stdenv,
  writeTextFile,
  fetchpatch,
  fetchurl,
  cmake,
  ninja,
  llvmPackages_12,
  llvmPackages_18,
  curl,
  tzdata,
  mimalloc,
  lit,
  gdb,
  unzip,
  darwin,
  xar,
  bash,
  pkg-config,
  makeWrapper,
  runCommand,
  targetPackages,
  hostDCompiler,
  ...
}:
let
  inherit (import ../../lib/build-status.nix { inherit lib; }) getBuildStatus;
  inherit (import ../../lib/version-utils.nix { inherit lib; }) versionBetween;
  buildStatus = getBuildStatus "ldc" version stdenv.system;

  # LDC tracks LLVM closely: 1.30 builds against LLVM 12, the 1.4x line needs
  # LLVM 15-20 (nixpkgs ships 1.40.1 on LLVM 18, so we use 18 here too).
  llvmPackages = if lib.versionAtLeast version "1.41.0" then llvmPackages_18 else llvmPackages_12;

  pathConfig = runCommand "phobos-tzdata-curl-paths" { } ''
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

  sharedMeta = with lib; {
    description = "The LLVM-based D compiler";
    homepage = "https://github.com/ldc-developers/ldc";
    # from https://github.com/ldc-developers/ldc/blob/master/LICENSE
    license = with licenses; [
      bsd3
      boost
      mit
      ncsa
      gpl2Plus
    ];
    maintainers = with maintainers; [
      ThomasMader
      lionello
    ];
    platforms = [
      "x86_64-linux"
      "i686-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "ldc2";
  };

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
  additionalExceptions = lib.optionalString stdenv.hostPlatform.isDarwin "|druntime-test-shared";

  # Attributes shared by the heavy build (untested) and the per-test stages. LDC
  # is CMake-based, so the test stages cannot cheaply restore a relocated build
  # tree (absolute paths are baked into the CMake cache); they instead rebuild
  # from source and run a single ctest group. This is dormant in practice: every
  # supported LDC source version currently has `check = false`, so no test stages
  # are emitted (see build-status.nix).
  commonAttrs = {
    inherit version;

    src = fetchurl {
      url = "https://github.com/ldc-developers/ldc/releases/download/v${version}/ldc-${version}-src.tar.gz";
      inherit sha256;
    };

    # https://issues.dlang.org/show_bug.cgi?id=19553
    hardeningDisable = [ "fortify" ];

    postUnpack = ''
      patchShebangs .
    ''
    # The remaining steps only massage the bundled dmd test suite, so they are
    # only needed when we actually run it. The paths below assume the pre-1.41
    # layout (`tests/d2/dmd-testsuite/`), which LDC 1.42 relocated to
    # `tests/dmd/`.
    + lib.optionalString buildStatus.check ''
      rm ldc-${version}-src/tests/d2/dmd-testsuite/fail_compilation/mixin_gc.d
      rm ldc-${version}-src/tests/d2/dmd-testsuite/runnable/xtest46_gc.d
      rm ldc-${version}-src/tests/d2/dmd-testsuite/runnable/testptrref_gc.d

      # test depends on current year
      rm ldc-${version}-src/tests/d2/dmd-testsuite/compilable/ddocYear.d
    ''
    + lib.optionalString (buildStatus.check && stdenv.hostPlatform.isDarwin) ''
      # https://github.com/NixOS/nixpkgs/issues/34817
      rm -r ldc-${version}-src/tests/plugins/addFuncEntryCall
    '';

    patches = lib.optionals (versionBetween "2.092.0" "2.101.0" version) [
      # `src/dmd/backend/cg.d` and `src/dmd/backend/var.d` contained arrays defined as
      # result from IIFE at CT. These function expressions were inside a
      # `extern (C++):` block, however they were returning static arrays, which
      # is not allowed in C++. This patch marks them as `extern (D)`, to avoid
      # this issue.
      # See: https://github.com/dlang/dmd/pull/14127
      (fetchpatch {
        url = "https://github.com/ldc-developers/ldc/commit/60079c3b596053b1a70f9f2e0cf38a287089df56.patch";
        sha256 = "sha256-Y/5+zt5ou9rzU7rLJq2OqUxMDvC7aSFS6AsPeDxNATQ=";
      })
    ];

    # These substitutions disarm dmd-testsuite / phobos unittests that fail in
    # the sandbox; they only matter when the test suite runs, and the
    # `tests/d2/dmd-testsuite/` path is the pre-1.41 layout.
    postPatch = lib.optionalString buildStatus.check (
      ''
        # Setting SHELL=$SHELL when dmd testsuite is run doesn't work on Linux somehow
        substituteInPlace tests/d2/dmd-testsuite/Makefile --replace "SHELL=/bin/bash" "SHELL=${bash}/bin/bash"
      ''
      + lib.optionalString stdenv.hostPlatform.isLinux ''
        substituteInPlace runtime/phobos/std/socket.d --replace "assert(ih.addrList[0] == 0x7F_00_00_01);" ""
      ''
      + lib.optionalString stdenv.hostPlatform.isDarwin ''
        substituteInPlace runtime/phobos/std/socket.d --replace "foreach (name; names)" "names = []; foreach (name; names)"
      ''
    );

    nativeBuildInputs = [
      cmake
      hostDCompiler
      lit
      lit.python
      llvmPackages.llvm.dev
      llvmPackages.lld.dev
      makeWrapper
      ninja
      unzip
      pkg-config
    ]
    ++ lib.optional stdenv.hostPlatform.isDarwin darwin.apple_sdk.frameworks.Foundation
    # https://github.com/NixOS/nixpkgs/pull/36378#issuecomment-385034818
    ++ lib.optional (!stdenv.hostPlatform.isDarwin) gdb;

    buildInputs = [
      curl
      tzdata
    ]
    # LLVM >= 18 reports `-lxar` in its system libs on macOS, and with
    # LDC_LINK_MANUALLY=ON the linker needs libxar on its search path.
    ++ lib.optional (stdenv.hostPlatform.isDarwin && lib.versionAtLeast version "1.41.0") xar;

    cmakeFlags =
      let
        # gold is a Linux-only linker; macOS uses the default (ld64/lld). LTO
        # default-libs and interprocedural optimization crash the freshly-built
        # LDC 1.42 compiler when it compiles the runtime on aarch64-darwin, so
        # the runtime there is built without LTO.
        useLto = !stdenv.hostPlatform.isDarwin;
        dFlags = [
          "-d-version=TZDatabaseDir"
          "-d-version=LibcurlPath"
          "-J${pathConfig}"
          "-O"
        ]
        ++ lib.optional (!stdenv.hostPlatform.isDarwin) "-linker=gold"
        ++ [
          "-defaultlib=${if useLto then "phobos2-ldc-lto,druntime-ldc-lto" else "phobos2-ldc,druntime-ldc"}"
        ];
      in
      [
        "-D D_FLAGS=${lib.concatStringsSep ";" dFlags}"
        "-D CMAKE_BUILD_TYPE=Release"
        "-D MULTILIB=OFF"
        "-D LDC_WITH_LLD=ON"
        "-D LDC_INSTALL_LLVM_RUNTIME_LIBS=ON"
        "-D BUILD_SHARED_LIBS=ON"
        "-D LDC_LINK_MANUALLY=ON"
        "-D RT_SUPPORT_SANITIZERS=ON"
      ]
      # The mimalloc object linked into ldc2 as its allocator crashes the
      # compiler during -O3 codegen on aarch64-darwin; only use it on Linux.
      ++ lib.optional (!stdenv.hostPlatform.isDarwin) "-D ALTERNATIVE_MALLOC_O=${mimalloc}/lib/mimalloc.o"
      ++ lib.optionals useLto [
        "-D BUILD_LTO_LIBS=ON"
        "-D LDC_INSTALL_LTOPLUGIN=ON"
        "-D CMAKE_INTERPROCEDURAL_OPTIMIZATION_CONFIG=ON"
      ];

    meta = sharedMeta;
  };

  postInstall =
    # LDC >= 1.41 installs a config *directory* (`etc/ldc2.conf/`, read as a
    # drop-in dir of `.conf` files); older LDC uses a single `etc/ldc2.conf`
    # file. Write our config to match the layout upstream produced.
    (
      if lib.versionAtLeast version "1.41.0" then
        ''
          substitute ${ldcConfFile} "$out/etc/ldc2.conf/50-nix.conf" --subst-var out
        ''
      else
        ''
          substitute ${ldcConfFile} "$out/etc/ldc2.conf" --subst-var out
        ''
    )
    + ''

      wrapProgram $out/bin/ldc2 \
        --prefix PATH ":" "${targetPackages.stdenv.cc}/bin" \
        --set-default CC "${targetPackages.stdenv.cc}/bin/cc"
    '';

  # The single, heavy from-source build: compiles and installs a real ldc
  # compiler, runs no tests. The final package below reuses this output verbatim
  # (so the compiler is compiled once), gated on the test stages.
  untested = stdenv.mkDerivation (
    commonAttrs
    // {
      pname = "ldc-untested";

      doCheck = false;

      inherit postInstall;

      passthru = {
        buildStatus = buildStatus // {
          check = false;
        };
      };
    }
  );

  # Shared prerequisites that must precede every ctest group (matches the order
  # of the original monolithic checkPhase).
  ldcCheckPreamble = ''
    ${lib.optionalString (buildStatus.skippedTests != [ ]) (
      lib.concatMapStringsSep "\n" (test: "rm -v ${test}") buildStatus.skippedTests
    )}
    # Build default lib test runners
    ninja -j$NIX_BUILD_CORES all-test-runners

    ${fixNames}
  '';

  # Each test stage rebuilds from source (see commonAttrs note) and runs only one
  # ctest group. Their union equals the original monolithic checkPhase.
  mkTest =
    { namePart, body }:
    stdenv.mkDerivation (
      commonAttrs
      // {
        pname = "ldc-${namePart}";

        doCheck = true;
        checkPhase = ''
          runHook preCheck
          ${ldcCheckPreamble}
          ${body}
          runHook postCheck
        '';

        # Tests only; the real install lives in the untested/final packages.
        installPhase = "touch $out";
        dontFixup = true;

        passthru = {
          inherit buildStatus;
        };
      }
    );

  testStageList = [
    {
      namePart = "dmd-testsuite-tests";
      body = ''
        export DMD_TESTSUITE_MAKE_ARGS="-j$NIX_BUILD_CORES DMD=$DMD"
        ctest -V -R "dmd-testsuite"
      '';
    }
    {
      namePart = "unittests";
      body = ''ctest --output-on-failure -R "ldc2-unittest"'';
    }
    {
      namePart = "lit-tests";
      body = ''ctest -V -R "lit-tests"'';
    }
    {
      namePart = "defaultlib-tests";
      body = ''ctest -j$NIX_BUILD_CORES --output-on-failure -E "ldc2-unittest|lit-tests|dmd-testsuite${additionalExceptions}"'';
    }
  ];

  # Test stages (and therefore the final package's gate) only exist when this
  # version/system is testable. When check is false we reproduce the old
  # `doCheck = false` behaviour: only the untested build and the final package.
  testStages = lib.optionals buildStatus.check (
    map (s: lib.nameValuePair s.namePart (mkTest s)) testStageList
  );
  testStageAttrs = lib.listToAttrs testStages;
  testStageDrvs = map (nv: nv.value) testStages;

  # The user-facing package: the untested install, gated on every test stage.
  # Referencing the stages forces Nix to build (and pass) them before realising
  # this package, so building ldc-${version} still means "everything built and
  # tested". The output is the untested install verbatim (built once).
  final =
    runCommand "ldc-${version}"
      {
        passthru = {
          inherit buildStatus;
          stages = {
            inherit untested;
          }
          // testStageAttrs;
        };
        meta = sharedMeta;
      }
      ''
        ${lib.concatMapStringsSep "\n" (d: ": ${d}") testStageDrvs}
        ln -s ${untested} $out
      '';
in
final
