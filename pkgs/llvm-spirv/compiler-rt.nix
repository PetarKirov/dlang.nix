# `compiler-rt-sparkles`: the runtimes of the fork's LLVM — builtins, the
# sanitizers (ASan, LSan, MSan, TSan, UBSan), profile, libFuzzer and XRay —
# built by `clang-sparkles` from the same `llvm-sparkles` source, so a
# `-fsanitize=`, `-fprofile-instr-generate`, `-fsanitize=fuzzer` or `-fxray`
# link from LDC or clang gets the runtime of the compiler that instrumented
# it (Sparkles' toolchain specification, TC10 and TC11).
#
# A standalone compiler-rt build reads only the monorepo's CMake modules, not
# an installed LLVM. The layout is clang's resource directory,
# `lib/clang/<major>/lib/<os>/`, which is also where LDC's
# `COMPILER_RT_BASE_DIR` looks (ldc-vulkan copies them into its own `lib/`).
# Flags follow nixpkgs' compiler-rt recipe.
{
  lib,
  stdenv,
  cmake,
  ninja,
  python3,
  jq,
  # The `llvm-sparkles` flake input.
  src,
  version,
}:
let
  major = lib.versions.major version;
  inherit (stdenv.hostPlatform) isDarwin;
in
stdenv.mkDerivation {
  pname = "compiler-rt-sparkles";
  inherit src version;

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ]
  ++ lib.optional isDarwin jq;

  cmakeDir = "../compiler-rt";

  postPatch = ''
    # codesign from sigtool rejects the options the build passes; the Nix
    # fixup phase signs instead.
    substituteInPlace compiler-rt/cmake/Modules/AddCompilerRT.cmake \
      --replace-fail 'find_program(CODESIGN codesign)' ""
  ''
  + lib.optionalString isDarwin ''
    # The arm64 probe reads SDKSettings.plist with PlistBuddy, whose xcbuild
    # stand-in answers differently; the SDK supports arm64, and
    # DARWIN_osx_BUILTIN_ARCHS limits what is built.
    substituteInPlace compiler-rt/cmake/builtin-config-ix.cmake \
      --replace-fail 'set(DARWIN_osx_BUILTIN_ALL_POSSIBLE_ARCHS ''${X86} ''${X86_64})' \
        'set(DARWIN_osx_BUILTIN_ALL_POSSIBLE_ARCHS ''${X86} ''${X86_64} ''${ARM64})' \
      --replace-fail 'sdk_has_arch_support(''${DARWIN_osx_SYSROOT} macosx ''${arch} MACOS_ARM_SUPPORT)' \
        'set(MACOS_ARM_SUPPORT FALSE)'
  '';

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    (lib.cmakeBool "COMPILER_RT_DEFAULT_TARGET_ONLY" true)
    (lib.cmakeFeature "CMAKE_C_COMPILER_TARGET" stdenv.hostPlatform.config)
    (lib.cmakeFeature "CMAKE_ASM_COMPILER_TARGET" stdenv.hostPlatform.config)
    (lib.cmakeFeature "COMPILER_RT_INSTALL_PATH" "lib/clang/${major}")
    (lib.cmakeBool "LLVM_ENABLE_PER_TARGET_RUNTIME_DIR" false)
    (lib.cmakeBool "COMPILER_RT_BUILD_BUILTINS" true)
    (lib.cmakeBool "COMPILER_RT_BUILD_SANITIZERS" true)
    (lib.cmakeBool "COMPILER_RT_BUILD_PROFILE" true)
    (lib.cmakeBool "COMPILER_RT_BUILD_LIBFUZZER" true)
    (lib.cmakeBool "COMPILER_RT_BUILD_XRAY" true)
    (lib.cmakeBool "COMPILER_RT_BUILD_MEMPROF" false)
    (lib.cmakeBool "COMPILER_RT_BUILD_ORC" false)
    (lib.cmakeBool "COMPILER_RT_BUILD_CTX_PROFILE" false)
    (lib.cmakeBool "COMPILER_RT_INCLUDE_TESTS" false)
  ]
  ++ lib.optionals isDarwin [
    (lib.cmakeFeature "CMAKE_LIPO" "${lib.getBin stdenv.cc.bintools.bintools}/bin/lipo")
    (lib.cmakeFeature "DARWIN_osx_ARCHS" stdenv.hostPlatform.darwinArch)
    (lib.cmakeFeature "DARWIN_osx_BUILTIN_ARCHS" stdenv.hostPlatform.darwinArch)
    (lib.cmakeFeature "SANITIZER_MIN_OSX_VERSION" stdenv.hostPlatform.darwinMinVersion)
    # COMPILER_RT_DEFAULT_TARGET_ONLY does not apply to Darwin.
    (lib.cmakeBool "COMPILER_RT_ENABLE_IOS" false)
  ];

  preConfigure = lib.optionalString isDarwin ''
    cmakeFlagsArray+=(
      "-DDARWIN_macosx_CACHED_SYSROOT=$SDKROOT"
      "-DDARWIN_macosx_OVERRIDE_SDK_VERSION=$(jq -r .Version "$SDKROOT/SDKSettings.json")"
    )
  '';

  passthru = {
    resourceLib = "lib/clang/${major}/lib";
    buildStatus = {
      build = true;
      check = false;
    };
  };

  meta = {
    description = "compiler-rt of the fork's LLVM, for clang-sparkles and ldc-vulkan";
    homepage = "https://github.com/PetarKirov/llvm-project/tree/sparkles/main";
    license = with lib.licenses; [
      mit
      ncsa
    ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
