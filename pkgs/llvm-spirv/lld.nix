# `lld-sparkles`: the lld of `llvm-spirv-vulkan` (the `lld` view of
# ./views.nix), with its ELF driver `ld.lld` behind nixpkgs' bintools wrapper,
# so a link through it records the store paths of its `-L` libraries as
# RUNPATH entries, names the libc's dynamic linker and applies the
# hardening flags, as a link through `ld` does. `wasm-ld`, `lld-link` and
# `ld64.lld` stay raw: their targets have no libc of the host's to wire in.
# Linux only.
#
# `passthru.bintools` is the wrapper itself, over GNU binutils and this lld:
# `ld` stays GNU ld, and `ld.lld` is the wrapped one. ./clang.nix takes it,
# so `-fuse-ld=lld` links through the wrapped `ld.lld`.
{
  lib,
  stdenv,
  symlinkJoin,
  wrapBintoolsWith,
  # The `lld` view of ./views.nix.
  lld,
}:
let
  bintools = wrapBintoolsWith {
    bintools = symlinkJoin {
      name = "binutils-lld-sparkles-${lld.version}";
      paths = [
        (lib.getBin stdenv.cc.bintools.bintools)
        lld
      ];
      passthru.isGNU = true;
    };
  };
in
symlinkJoin {
  name = "lld-sparkles-${lld.version}";
  paths = [ lld ];
  postBuild = ''
    rm $out/bin/ld.lld
    ln -s ${bintools}/bin/ld.lld $out/bin/ld.lld
  '';
  passthru = {
    inherit bintools;
    inherit (lld) version;
    buildStatus = {
      build = true;
      check = false;
    };
  };
  meta = {
    description = "lld of llvm-spirv-vulkan, with ld.lld behind the Nix bintools wrapper";
    homepage = "https://lld.llvm.org/";
    license = with lib.licenses; [
      asl20
      llvm-exception
    ];
    platforms = lib.platforms.linux;
  };
}
