# `llvm-runtimes-sparkles`: LLVM's libunwind, libc++abi and libc++ for the
# host, built by `clang-sparkles` from the `llvm-sparkles` source, for the
# all-LLVM runtime profile (Sparkles' toolchain specification, TC18). Linux
# only: on macOS, the system's libc++ and unwinder already are LLVM's.
#
# Every library links compiler-rt's builtins and LLVM's libunwind, never
# libgcc or libgcc_s, so a program of the profile loads one unwinder (TC19).
# Each comes as a shared and a static library; libc++.a carries libc++abi,
# so a static link names libc++ and libunwind only.
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
stdenv.mkDerivation {
  pname = "llvm-runtimes-sparkles";
  inherit version src;

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  cmakeDir = "../runtimes";
  cmakeFlags = [
    "-DLLVM_ENABLE_RUNTIMES=libunwind;libcxxabi;libcxx"
    "-DLIBUNWIND_USE_COMPILER_RT=ON"
    "-DLIBUNWIND_INCLUDE_TESTS=OFF"
    "-DLIBCXXABI_USE_COMPILER_RT=ON"
    "-DLIBCXXABI_USE_LLVM_UNWINDER=ON"
    "-DLIBCXXABI_INCLUDE_TESTS=OFF"
    "-DLIBCXX_CXX_ABI=libcxxabi"
    "-DLIBCXX_USE_COMPILER_RT=ON"
    "-DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON"
    "-DLIBCXX_INCLUDE_TESTS=OFF"
    "-DLIBCXX_INCLUDE_BENCHMARKS=OFF"
  ];

  passthru = {
    # Tells the cc-wrapper this is LLVM's libc++ (`-stdlib=libc++`).
    isLLVM = true;
    buildStatus = {
      build = true;
      check = false;
    };
  };

  meta = {
    description = "LLVM's libunwind, libc++abi and libc++, from the fork the toolchain is built from";
    homepage = "https://libcxx.llvm.org/";
    license = with lib.licenses; [
      asl20
      llvm-exception
    ];
    platforms = lib.platforms.linux;
  };
}
