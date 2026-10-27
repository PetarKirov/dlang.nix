# `clang-sparkles`: a cc-wrapper over the clang that `llvm-spirv-vulkan`
# builds, as cut out of the install by ./views.nix, so C and C++ compile with
# the same clang and LLVM as `ldc-vulkan`, and `overrideCC stdenv
# clang-sparkles` is a stdenv for it.
#
# The wrapper is the layer nixpkgs puts over every compiler: the libc and C++
# library headers, rpaths and hardening. What the view lacks is borrowed:
#
# - Linux: libstdc++ from stdenv's gcc, as nixpkgs' `clangStdenv` does.
# - Darwin: stdenv's libc++.
#
# The resource directory is the view's built-in headers plus the runtimes of
# `compiler-rt`. ./compiler-rt.nix is itself built by this wrapper, so it is
# applied twice: first with nixpkgs' compiler-rt on Darwin (whose builtins
# archive every Darwin link pulls in, with an ABI that does not change with
# the compiler) and none on Linux, where libgcc is clang's default runtime;
# then with the fork's own.
{
  lib,
  stdenv,
  wrapCCWith,
  # The `clang` view of ./views.nix.
  cc,
  # A compiler-rt whose `lib/clang/<major>/lib` (or, for nixpkgs', `lib`)
  # holds the runtimes; null for none.
  compiler-rt ? null,
}:
let
  major = lib.versions.major cc.version;
  inherit (stdenv.hostPlatform) isDarwin;
  runtimeLib =
    if compiler-rt == null then
      null
    else
      "${compiler-rt.out}/${compiler-rt.passthru.resourceLib or "lib"}";
in
(wrapCCWith {
  inherit cc;
  libcxx = if isDarwin then stdenv.cc.libcxx else null;
  extraPackages = lib.optional (compiler-rt != null) compiler-rt;
  # The resource directory nixpkgs' own clang wrappers assemble.
  extraBuildCommands = ''
    rsrc="$out/resource-root"
    mkdir "$rsrc"
    ln -s "${cc}/lib/clang/${major}/include" "$rsrc"
    echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
  ''
  + lib.optionalString (runtimeLib != null) ''
    ln -s "${runtimeLib}" "$rsrc/lib"
  '';
}).overrideAttrs
  (old: {
    passthru = old.passthru // {
      buildStatus = {
        build = true;
        check = false;
      };
    };
  })
