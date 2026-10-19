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

  patches = [
    ./vulkan-physical-storage-buffer.patch
    # Signed integers in modules that set the `spirv.signed-integers` flag, and
    # `OpMemberName` from `spirv.MemberNames` metadata: what ldc-vulkan needs
    # for a shader's `int` and struct uniforms to reach GLSL as `int` and with
    # their field names, rather than `uint` and `_m0`.
    ./spirv-signed-ints-member-names.patch
    # Literal access-chain indices as `i32`, not `i64`: an optimised read of
    # a uniform struct's field otherwise needs `Int64`, which a GLSL ES 1.00
    # cross-compile rejects.
    ./spirv-access-chain-i32-indices.patch
    # On top of #216919: buffer device addresses only for a module that asks
    # (`spirv.physical-storage-buffer`), which keeps every upstream test
    # passing; `p[i]` on one as an OpPtrAccessChain (also when an optimiser
    # wrote it as a byte offset, which dropped the index), with the ArrayStride
    # and Aligned Vulkan requires.
    ./vulkan-physical-storage-buffer-opt-in.patch
    # A resource's name string is not materialised, so a shader with a named
    # resource no longer declares Int8.
    ./spirv-resource-name-no-int8.patch
    # `llvm.spv.terminate.invocation`: GLSL's `discard` (OpTerminateInvocation),
    # where `llvm.spv.discard` demotes from SPIR-V 1.6 on.
    ./spirv-terminate-invocation.patch
    # Nested conditions whose exits meet an enclosing one's (early returns)
    # get merge blocks of their own instead of escaping their parents.
    ./spirv-structurizer-nested-shared-exits.patch
    # Explicit block layout (std140 uniform blocks, std430 push constants):
    # a buffer laid out with `spirv.Layout` can be read by member; a peeled
    # cbuffer array lowers to `T[N]` with the padded stride and no `Int8`
    # member; a laid-out struct is named once.
    ./spirv-layout-buffer-members.patch
    ./spirv-peeled-array-strided.patch
    ./spirv-layout-single-name.patch
    # No 64-bit integers a shader did not ask for: a logical access chain
    # indexes with the 32-bit value a frontend widened (D's `size_t`), and
    # folds whole element steps (`t[i + 1]`) into the index instead of
    # asserting; a memset of a whole local is a store.
    ./spirv-access-chain-narrow-indices.patch
    ./spirv-memset-whole-object.patch
    ./spirv-access-chain-element-steps.patch
    # In signed-integer mode, `OpUDiv`, `OpUMod` and `OpConvertFToU` compute
    # in an unsigned type, which SPIR-V requires of their result.
    ./spirv-unsigned-ops-signed-mode.patch
    # The vertex stage: a global named by `spirv.Name` metadata, so a vertex
    # output and the fragment input it feeds share their name in one module,
    # and each shader entry point's interface lists only what it uses.
    ./spirv-global-name-metadata.patch
    ./spirv-entry-point-interface-per-entry.patch
  ];

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
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
