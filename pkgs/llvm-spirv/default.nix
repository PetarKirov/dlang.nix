# `llvm-spirv-vulkan`: the LLVM that `ldc-vulkan` is built against — the
# PetarKirov/llvm-project `sparkles/main` branch (the `llvm-sparkles` input):
# LLVM main (24.0.0git) with llvm/llvm-project#216919 (PhysicalStorageBuffer
# addressing and struct block wrapping for Vulkan, by Pham Quang Ha as part of
# GSoC 2026's DCompute Vulkan backend) and the SPIR-V fixes dcompute's Vulkan
# shaders need, one atomic commit each, kept rebased on upstream until they
# land. `git log upstream/main..sparkles/main` lists them with their reasons.
#
# Why not an `llvmPackages_*` set: no nixpkgs release ships LLVM 24 yet, and
# LDC only needs `llvm-config` plus the static libraries of LLVM and lld. One
# install prefix holds both, so it doubles as `llvm.dev` and `lld.dev` for
# ./../ldc/generic.nix (see `llvmPackages` in ./../default.nix). Clang and lld
# are built too, as clang-sparkles and the compiler and linker of the WASI
# sysroots (../wasi): D, C and the link then share one LLVM.
#
# Targets are AArch64 and X86 (every desktop host, and Android devices and
# emulators, from either host), SPIRV (for dcompute's Vulkan target) and
# WebAssembly (for the WASI runtime), so one LDC serves them all.
# Assertions stay on: the SPIR-V backend is young, and an assertion that
# fires in a shader build is a bug report, not a slowdown. A release variant
# beside it would share nothing (LDC links LLVM statically), so there is one
# (Sparkles' toolchain specification, TC17 and TCD8).
#
# The tools link one shared `libLLVM` and `libclang-cpp` instead of each
# carrying a static copy of LLVM; the static libraries are still installed,
# for LDC. Tools nothing here uses are not built. This install is a build
# input: what a runtime closure needs comes from ./views.nix.
{
  lib,
  stdenv,
  cmake,
  ninja,
  python3,
  # The `llvm-sparkles` flake input.
  src,
  version,
}:
let
  # clang/tools and llvm/tools directories, as CMake spells them. Kept: the
  # clang driver and `clang-shlib`; llc, opt, llvm-as, -dis and -link; the
  # binutils (ar, nm, objcopy, objdump, readobj, size, strings); llvm-config;
  # the profile, coverage, symbolizer, XRay and sancov tools that pair with
  # compiler-rt's runtimes; dsymutil, llvm-lipo, libLTO and llvm-shlib.
  unusedClangTools = [
    "APINOTES_TEST"
    "C_INDEX_TEST"
    "CLANG_CHECK"
    "CLANG_DIFF"
    "CLANG_EXTDEF_MAPPING"
    "CLANG_FORMAT"
    "CLANG_FUZZER"
    "CLANG_IMPORT_TEST"
    "CLANG_INSTALLAPI"
    "CLANG_LINKER_WRAPPER"
    "CLANG_NVLINK_WRAPPER"
    "CLANG_OFFLOAD_BUNDLER"
    "CLANG_REFACTOR"
    "CLANG_REPL"
    "CLANG_SCAN_DEPS"
    "CLANG_SSAF_ANALYZER"
    "CLANG_SSAF_FORMAT"
    "CLANG_SSAF_LINKER"
    "CLANG_SSAF_SRC_EDIT_MERGE"
    "CLANG_SYCL_LINKER"
    "DIAGTOOL"
    "LIBCLANG"
    "OFFLOAD_ARCH"
    "SCAN_BUILD"
    "SCAN_BUILD_PY"
    "SCAN_VIEW"
  ];
  unusedLlvmTools = [
    "DXIL_DIS"
    "LLI"
    "LLUBI"
    "LLVM_BCANALYZER"
    "LLVM_C_TEST"
    "LLVM_CALC_OCCUPANCY"
    "LLVM_CAS"
    "LLVM_CAT"
    "LLVM_CFI_VERIFY"
    "LLVM_CGDATA"
    "LLVM_CTXPROF_UTIL"
    "LLVM_CVTRES"
    "LLVM_CXXDUMP"
    "LLVM_CXXMAP"
    "LLVM_DEBUGINFO_ANALYZER"
    "LLVM_DEBUGINFOD"
    "LLVM_DEBUGINFOD_FIND"
    "LLVM_DIFF"
    "LLVM_DWARFUTIL"
    "LLVM_DWP"
    "LLVM_EXEGESIS"
    "LLVM_EXTRACT"
    "LLVM_GPU_LOADER"
    "LLVM_GSYMUTIL"
    "LLVM_IFS"
    "LLVM_IR2VEC"
    "LLVM_JITLINK"
    "LLVM_JITLISTENER"
    "LLVM_LIBTOOL_DARWIN"
    "LLVM_LTO"
    "LLVM_LTO2"
    "LLVM_MCA"
    "LLVM_ML"
    "LLVM_MODEXTRACT"
    "LLVM_MT"
    "LLVM_OFFLOAD_BINARY"
    "LLVM_OFFLOAD_WRAPPER"
    "LLVM_OPT_REPORT"
    "LLVM_PDBUTIL"
    "LLVM_PROFGEN"
    "LLVM_RC"
    "LLVM_READTAPI"
    "LLVM_REDUCE"
    "LLVM_REMARKUTIL"
    "LLVM_RTDYLD"
    "LLVM_SPLIT"
    "LLVM_STRESS"
    "LLVM_TLI_CHECKER"
    "LLVM_UNDNAME"
    "OBJ2YAML"
    "OPT_VIEWER"
    "REDUCE_CHUNK_LIST"
    "SANSTATS"
    "SPIRV_TOOLS"
    "VERIFY_USELISTORDER"
    "XCODE_TOOLCHAIN"
    "YAML2OBJ"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "llvm-spirv-vulkan";
  inherit src version;

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
    (lib.cmakeFeature "LLVM_ENABLE_PROJECTS" "clang;lld")
    (lib.cmakeFeature "LLVM_TARGETS_TO_BUILD" "AArch64;X86;SPIRV;WebAssembly")
    (lib.cmakeBool "LLVM_ENABLE_ASSERTIONS" true)
    # Clang is the WASI C driver only.
    (lib.cmakeBool "CLANG_ENABLE_STATIC_ANALYZER" false)
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
    (lib.cmakeBool "LLVM_BUILD_LLVM_DYLIB" true)
    (lib.cmakeBool "LLVM_LINK_LLVM_DYLIB" true)
    (lib.cmakeBool "CLANG_LINK_CLANG_DYLIB" true)
    # FileCheck, `not` and `count`, for LDC's lit tests.
    (lib.cmakeBool "LLVM_INSTALL_UTILS" true)
  ]
  ++ map (tool: lib.cmakeBool "CLANG_TOOL_${tool}_BUILD" false) unusedClangTools
  ++ map (tool: lib.cmakeBool "LLVM_TOOL_${tool}_BUILD" false) unusedLlvmTools;

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
    description = "LLVM main with the SPIR-V fixes of dcompute's Vulkan target, for ldc-vulkan";
    homepage = "https://github.com/PetarKirov/llvm-project/tree/sparkles/main";
    license = lib.licenses.ncsa;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
