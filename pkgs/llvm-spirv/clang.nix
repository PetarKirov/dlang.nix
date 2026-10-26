# `clang-sparkles`: a cc-wrapper over the clang that `llvm-spirv-vulkan`
# already builds, so C and C++ compile with the same clang and LLVM as
# `ldc-vulkan`, and `overrideCC stdenv clang-sparkles` is a stdenv for it.
#
# The wrapper is the layer nixpkgs puts over every compiler: the libc and C++
# library headers, rpaths and hardening. It only links to the LLVM install, so
# none of it rebuilds LLVM. What that install lacks is borrowed:
#
# - Linux: libstdc++ from stdenv's gcc, as nixpkgs' `clangStdenv` does; no
#   compiler-rt, as libgcc is clang's default runtime there.
# - Darwin: stdenv's libc++, and the builtins archive (`libclang_rt.osx.a`,
#   which every Darwin link pulls in) from nixpkgs' compiler-rt, whose ABI does
#   not change with the compiler's version.
{
  lib,
  stdenv,
  wrapCCWith,
  # The `llvm-spirv-vulkan` install: LLVM, clang and lld under one prefix.
  llvm,
  # Darwin's builtins archive.
  compiler-rt,
}:
let
  major = lib.versions.major llvm.version;
  inherit (stdenv.hostPlatform) isDarwin;
in
wrapCCWith {
  # What kind of compiler it wraps is read from `passthru`, which is not part
  # of the derivation: the store path stays the LLVM install's.
  cc = llvm.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      isClang = true;
      langC = true;
      langCC = true;
    };
  });
  libcxx = if isDarwin then stdenv.cc.libcxx else null;
  extraPackages = lib.optional isDarwin compiler-rt;
  # The resource directory nixpkgs' own clang wrappers assemble: the
  # install's built-in headers, and on Darwin compiler-rt's libraries.
  extraBuildCommands = ''
    rsrc="$out/resource-root"
    mkdir "$rsrc"
    ln -s "${llvm}/lib/clang/${major}/include" "$rsrc"
    echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
  ''
  + lib.optionalString isDarwin ''
    ln -s "${compiler-rt.out}/lib" "$rsrc/lib"
  '';
}
