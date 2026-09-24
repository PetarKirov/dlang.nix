# `llvm-spirv-vulkan`: the LLVM that `ldc-vulkan` is built against — LLVM main
# (24.0.0git) with the SPIR-V backend, plus llvm/llvm-project#216919
# (PhysicalStorageBuffer addressing and struct block wrapping for Vulkan, by
# Pham Quang Ha as part of GSoC 2026's DCompute Vulkan backend), vendored as
# ./vulkan-physical-storage-buffer.patch until it lands upstream.
#
# Why not an `llvmPackages_*` set: no nixpkgs release ships LLVM 24 yet, and
# LDC only needs `llvm-config` plus the static libraries of LLVM and lld. One
# install prefix holds both, so it doubles as `llvm.dev` and `lld.dev` for
# ./../ldc/generic.nix (see `llvmPackages` in ./../default.nix).
#
# Targets are the host (for LDC's own runtime) and SPIRV (for dcompute's
# Vulkan target). Assertions stay on: the SPIR-V backend is young, and an
# assertion that fires in a shader build is a bug report, not a slowdown.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  python3,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "llvm-spirv-vulkan";
  version = "24.0.0-unstable-2026-09-19";

  src = fetchFromGitHub {
    owner = "llvm";
    repo = "llvm-project";
    rev = "27ba493781215910f560b36cd5b3b2f6c93ec5a3";
    hash = "sha256-vPDuGe7NT61BguGV1SP1TBCkwX4c/a+Xzc0BaL0pSgY=";
  };

  patches = [ ./vulkan-physical-storage-buffer.patch ];

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  # The monorepo root is the source root (the patch is monorepo-relative);
  # CMake configures the `llvm/` subproject from the build directory.
  cmakeDir = "../llvm";

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    (lib.cmakeFeature "LLVM_ENABLE_PROJECTS" "lld")
    (lib.cmakeFeature "LLVM_TARGETS_TO_BUILD" "host;SPIRV")
    (lib.cmakeBool "LLVM_ENABLE_ASSERTIONS" true)
    (lib.cmakeBool "LLVM_INCLUDE_TESTS" false)
    (lib.cmakeBool "LLVM_INCLUDE_BENCHMARKS" false)
    (lib.cmakeBool "LLVM_INCLUDE_EXAMPLES" false)
    (lib.cmakeBool "LLVM_INCLUDE_DOCS" false)
    (lib.cmakeBool "LLVM_ENABLE_BINDINGS" false)
    # No optional system libraries: `llvm-config --system-libs` would then ask
    # every LDC link for them, and none of them matters to a shader compiler.
    (lib.cmakeBool "LLVM_ENABLE_ZLIB" false)
    (lib.cmakeBool "LLVM_ENABLE_ZSTD" false)
    (lib.cmakeBool "LLVM_ENABLE_LIBXML2" false)
    (lib.cmakeBool "LLVM_ENABLE_LIBEDIT" false)
    (lib.cmakeBool "LLVM_ENABLE_TERMINFO" false)
    # Static LLVM links are the memory peak of this build.
    (lib.cmakeFeature "LLVM_PARALLEL_LINK_JOBS" "4")
  ];

  passthru = {
    # ./../ldc/generic.nix reads `llvmPackages.llvm.dev` / `.lld.dev`.
    dev = finalAttrs.finalPackage;
    buildStatus = {
      build = true;
      check = false;
      skippedTests = [ ];
    };
  };

  meta = {
    description = "LLVM main with the SPIR-V backend and the Vulkan PhysicalStorageBuffer fixes, for ldc-vulkan";
    homepage = "https://github.com/llvm/llvm-project/pull/216919";
    license = lib.licenses.ncsa;
    platforms = lib.platforms.linux;
  };
})
