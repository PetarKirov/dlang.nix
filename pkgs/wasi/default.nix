# The C side of WASI, built from source by the fork's clang (Sparkles'
# toolchain specification, wasi.md, TCW1–TCW6): for each preview, compiler-rt's
# `wasm32` builtins, wasi-libc, and libc++/libc++abi/libunwind with
# WebAssembly exceptions in the standardized encoding (`exnref`), each with a
# link-time-optimization variant that the same LLVM reads; and a driver,
# `wasm32-wasipN-clang`, that compiles and links against them. Preview 2 and 3
# links go through `wasm-component-ld` and produce components.
#
# Preview 1 and 2 are production targets; preview 3 is experimental (TCW2).
# The recipe follows wasi-sdk's (cmake/wasi-sdk-sysroot.cmake).
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  cmake,
  ninja,
  python3,
  runtimeShell,
  symlinkJoin,
  runCommand,
  wasm-component-ld,
  wasm-tools,
  wit-bindgen,
  wkg,
  # The `clang` view of the fork's LLVM (../llvm-spirv/views.nix).
  clang,
  # The fork's monorepo (the `llvm-sparkles` input).
  llvmSrc,
}:
let
  inherit (clang) version;
  major = lib.versions.major version;

  # wasi-libc's development branch: preview 3 lives only there, and one
  # revision serves every preview.
  wasiLibcSrc = fetchFromGitHub {
    owner = "WebAssembly";
    repo = "wasi-libc";
    rev = "f6e9006376e6f8e8f91ab84fc956be4e345588bc";
    hash = "sha256-aJj+FsDTvzh/O//mO7GNGVrdULE8kIa2r57LN80FpP4=";
  };

  # Preview 3 is allowed to fail: its `build` is false, which the CI matrix
  # reads as allowed to fail, and no aggregate depends on it (TCW2).
  status = experimental: {
    build = !experimental;
    check = false;
  };

  # A CMake cross build for WASI with the bare clang of the view.
  crossFlags = [
    "-DCMAKE_SYSTEM_NAME=WASI"
    "-DCMAKE_SYSTEM_VERSION=1"
    "-DCMAKE_SYSTEM_PROCESSOR=wasm32"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_C_COMPILER=${clang}/bin/clang"
    "-DCMAKE_CXX_COMPILER=${clang}/bin/clang++"
    "-DCMAKE_AR=${clang}/bin/llvm-ar"
    "-DCMAKE_RANLIB=${clang}/bin/llvm-ranlib"
    "-DCMAKE_C_COMPILER_WORKS=ON"
    "-DCMAKE_CXX_COMPILER_WORKS=ON"
    # wasm-ld has no depfile flag, which CMake infers from a bare clang.
    "-DCMAKE_C_LINKER_DEPFILE_SUPPORTED=OFF"
    "-DCMAKE_CXX_LINKER_DEPFILE_SUPPORTED=OFF"
  ];

  # Preview 2 and 3 libraries are position-independent, as in wasi-sdk.
  picFlag = preview: lib.optionalString (preview != "wasip1") "-fPIC";

  # The linkers clang runs for WASI, found through `-B`: `wasm-ld`, and
  # `wasm-component-ld`, which preview 2 and 3 links go through and which
  # calls `wasm-ld` in turn.
  linkers = runCommand "wasi-linkers-${version}" { } ''
    mkdir -p $out
    ln -s ${clang}/bin/wasm-ld $out/wasm-ld
    ln -s ${lib.getExe wasm-component-ld} $out/wasm-component-ld
  '';

  mkPreview =
    preview:
    let
      target = "wasm32-${preview}";
      experimental = preview == "wasip3";

      # Builtins for the target; wasi-sdk reuses preview 1's for preview 2.
      builtins = stdenvNoCC.mkDerivation {
        pname = "compiler-rt-builtins-${target}";
        inherit version;
        src = llvmSrc;
        nativeBuildInputs = [
          cmake
          ninja
          python3
        ];
        cmakeDir = "../compiler-rt";
        cmakeFlags = crossFlags ++ [
          "-DCMAKE_C_COMPILER_TARGET=${target}"
          "-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON"
          "-DCOMPILER_RT_BAREMETAL_BUILD=ON"
          "-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON"
          "-DCOMPILER_RT_HAS_FPIC_FLAG=OFF"
          "-DCOMPILER_RT_INCLUDE_TESTS=OFF"
          "-DCOMPILER_RT_BUILD_SANITIZERS=OFF"
          "-DCOMPILER_RT_BUILD_XRAY=OFF"
          "-DCOMPILER_RT_BUILD_LIBFUZZER=OFF"
          "-DCOMPILER_RT_BUILD_PROFILE=OFF"
          "-DCOMPILER_RT_BUILD_CTX_PROFILE=OFF"
          "-DCOMPILER_RT_BUILD_MEMPROF=OFF"
          "-DCOMPILER_RT_BUILD_ORC=OFF"
          "-DCOMPILER_RT_BUILD_GWP_ASAN=OFF"
        ];
        passthru.buildStatus = status experimental;
      };
      builtinsLib = "${builtins}/lib/wasm32-unknown-${preview}/libclang_rt.builtins.a";

      # The resource directory the driver and the library builds use:
      # clang's built-in headers and this preview's builtins.
      resourceDir = symlinkJoin {
        name = "wasi-resource-dir-${target}-${version}";
        paths = [ builtins ];
        postBuild = ''
          ln -s ${clang}/lib/clang/${major}/include $out/include
        '';
      };

      libc =
        lto:
        stdenvNoCC.mkDerivation {
          pname = "wasi-libc-${target}${lib.optionalString lto "-lto"}";
          # Flags with spaces stay one argument each.
          __structuredAttrs = true;
          version = "0-unstable-2026-10-21";
          src = wasiLibcSrc;
          patches = [ ./patches/wasi-libc-0001-ldexp-keep-the-scalbn-call-a-call.patch ];
          nativeBuildInputs = [
            cmake
            ninja
            python3
            wasm-tools
            wit-bindgen
            wkg
          ];
          # The build only uses `wkg` to vendor WIT files, which are committed;
          # nixpkgs' 0.15.1 serves as well as the 0.15.0 the check names, so
          # nothing is downloaded.
          postPatch = ''
            substituteInPlace cmake/wasi-wits.cmake \
              --replace-fail 'MATCHES "0\\.15\\.0"' 'MATCHES "0\\.15\\."'
          '';
          cmakeFlags =
            crossFlags
            ++ [
              "-DTARGET_TRIPLE=${target}"
              "-DBUILTINS_LIB=${builtinsLib}"
              "-DUSE_WASM_COMPONENT_LD=OFF"
              "-DCMAKE_C_FLAGS=-resource-dir=${resourceDir} -B${linkers} ${picFlag preview}"
              "-DCMAKE_ASM_FLAGS=-resource-dir=${resourceDir} -B${linkers} ${picFlag preview}"
            ]
            ++ lib.optionals lto [
              "-DLTO=full"
              "-DBUILD_SHARED=OFF"
            ];
          passthru.buildStatus = status experimental;
        };

      libcxx =
        lto: libc:
        stdenvNoCC.mkDerivation {
          pname = "wasi-libcxx-${target}${lib.optionalString lto "-lto"}";
          __structuredAttrs = true;
          inherit version;
          src = llvmSrc;
          nativeBuildInputs = [
            cmake
            ninja
            python3
          ];
          cmakeDir = "../runtimes";
          # LTO libraries go where clang looks for them: `lib/<target>/llvm-lto/`
          # and the version clang reports, as wasi-libc does.
          preConfigure = ''
            libdir=/${target}${lib.optionalString lto "/llvm-lto/$(${clang}/bin/clang -dumpversion)"}
            cmakeFlagsArray+=(
              -DLIBCXX_LIBDIR_SUFFIX=$libdir
              -DLIBCXXABI_LIBDIR_SUFFIX=$libdir
              -DLIBUNWIND_LIBDIR_SUFFIX=$libdir
            )
          '';
          cmakeFlags =
            let
              flags = lib.concatStringsSep " " (
                [
                  "--target=${target}"
                  "--sysroot=${libc}"
                  "-resource-dir=${resourceDir}"
                  "-B${linkers}"
                  "-fwasm-exceptions"
                  "-mllvm"
                  "-wasm-use-legacy-eh=false"
                ]
                ++ lib.optional (!lto) (picFlag preview)
                ++ lib.optional lto "-flto=full"
              );
            in
            crossFlags
            ++ [
              "-DLLVM_ENABLE_RUNTIMES=libunwind;libcxxabi;libcxx"
              "-DCMAKE_SYSROOT=${libc}"
              "-DCMAKE_C_FLAGS=${flags}"
              "-DCMAKE_CXX_FLAGS=${flags}"
              "-DCMAKE_ASM_FLAGS=${flags}"
              "-DLLVM_COMPILER_CHECKED=ON"
              "-DLIBCXX_ENABLE_THREADS=ON"
              "-DLIBCXX_HAS_PTHREAD_API=ON"
              "-DLIBCXX_HAS_EXTERNAL_THREAD_API=OFF"
              "-DLIBCXX_HAS_WIN32_THREAD_API=OFF"
              "-DLIBCXX_ENABLE_SHARED=OFF"
              "-DLIBCXX_ENABLE_EXCEPTIONS=ON"
              "-DLIBCXX_ENABLE_FILESYSTEM=ON"
              "-DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF"
              "-DLIBCXX_CXX_ABI=libcxxabi"
              "-DLIBCXX_HAS_MUSL_LIBC=OFF"
              "-DLIBCXX_ABI_VERSION=2"
              "-DLIBCXX_INCLUDE_TESTS=OFF"
              "-DLIBCXX_INCLUDE_BENCHMARKS=OFF"
              "-DLIBCXXABI_ENABLE_EXCEPTIONS=ON"
              "-DLIBCXXABI_ENABLE_SHARED=OFF"
              "-DLIBCXXABI_SILENT_TERMINATE=ON"
              "-DLIBCXXABI_ENABLE_THREADS=ON"
              "-DLIBCXXABI_HAS_PTHREAD_API=ON"
              "-DLIBCXXABI_HAS_EXTERNAL_THREAD_API=OFF"
              "-DLIBCXXABI_HAS_WIN32_THREAD_API=OFF"
              "-DLIBCXXABI_USE_LLVM_UNWINDER=ON"
              "-DLIBUNWIND_ENABLE_SHARED=OFF"
              "-DLIBUNWIND_ENABLE_THREADS=ON"
              "-DLIBUNWIND_USE_COMPILER_RT=ON"
              "-DLIBUNWIND_INCLUDE_TESTS=OFF"
              "-DUNIX=ON"
              "-DCMAKE_INSTALL_INCLUDEDIR=include/${target}"
            ];
          passthru.buildStatus = status experimental;
        };

      libcPlain = libc false;
      libcLto = libc true;

      # One sysroot: headers and libraries, with the LTO builds under
      # `lib/<target>/llvm-lto/<version>`, where clang looks for them.
      sysroot = symlinkJoin {
        name = "wasi-sysroot-${target}-${version}";
        paths = [
          libcPlain
          libcLto
          (libcxx false libcPlain)
          (libcxx true libcPlain)
        ];
        # clang finds libc++'s version under the generic `include/c++/` before it
        # looks in the per-target directory; one preview per sysroot, so the
        # generic one is the target's.
        postBuild = ''
          ln -s ${target}/c++ $out/include/c++
        '';
        passthru.buildStatus = status experimental;
      };

      # `wasm32-wasipN-clang{,++}`: clang configured for the preview. Preview
      # 2 and 3 links go through `wasm-component-ld`, which clang picks for
      # those targets when it is next to its linker.
      driver = stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "wasi-driver-${target}";
        inherit version;
        dontUnpack = true;
        installPhase = ''
          mkdir -p $out/bin
          for exe in clang clang++; do
            substitute ${./driver.sh} $out/bin/${target}-$exe \
              --subst-var-by shell ${runtimeShell} \
              --subst-var-by clang ${clang} \
              --subst-var-by exe $exe \
              --subst-var-by target ${target} \
              --subst-var-by sysroot ${sysroot} \
              --subst-var-by resourceDir ${resourceDir} \
              --subst-var-by libexec ${linkers}
            chmod +x $out/bin/${target}-$exe
          done
        '';
        passthru = {
          buildStatus = status experimental;
          inherit
            target
            sysroot
            resourceDir
            builtins
            ;
          cc = "${finalAttrs.finalPackage}/bin/${target}-clang";
        };
      });
    in
    driver;
in
lib.genAttrs [
  "wasip1"
  "wasip2"
  "wasip3"
] mkPreview
