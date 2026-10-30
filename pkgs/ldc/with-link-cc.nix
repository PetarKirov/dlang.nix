# An LDC built with generic.nix's `wrapLinkCc = false`, plus `ldc2` and
# `ldmd2` wrappers that default `CC` to the C compiler LDC links through
# (and use for ImportC). The compiler itself references no C compiler, so a
# closure that only compiles takes `passthru.unwrapped` and carries none:
# for `ldc-vulkan`, that is clang, GCC (clang's C++ library and start files
# on Linux) and compiler-rt.
#
# Both drivers are wrapped: `ldmd2` runs the `ldc2` beside it, which is the
# unwrapped one.
{
  lib,
  stdenv,
  symlinkJoin,
  makeWrapper,
  cctools,
  darwin,
  ldc,
  # A cc-wrapped C compiler (`clang-sparkles`).
  cc,
}:
let
  # ldc2 passes the compiler an explicit `-target`, which a nix-wrapped clang
  # warns about when it differs from its own spelling; a Darwin link with
  # debug info runs dsymutil, which ships beside the wrapped clang.
  flags = [
    "--prefix PATH : ${cc}/bin"
    "--set-default CC ${cc}/bin/cc"
    "--set-default NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING 1"
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin "--set-default DSYMUTIL ${cc.cc}/bin/dsymutil";
in
symlinkJoin {
  inherit (ldc) name;
  paths = [ ldc ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild =
    lib.optionalString stdenv.hostPlatform.isDarwin ''
      # LLVM's libLTO.dylib, which LDC hands ld64 for LTO (`-lto_library`),
      # links @rpath/libLLVM.*.dylib, and LDC's lib/ has no libLLVM. The clang
      # the wrapper links through has it, so this copy finds it there; the
      # unwrapped LDC's stays without, keeping clang out of its closure. The
      # wrapped drivers run the unwrapped ldc2, which would pick the
      # libLTO.dylib beside itself, so they name this copy.
      ltoFlags=
      if [ -e $out/lib/libLTO.dylib ]; then
        # install_name_tool, and the codesign_allocate codesign runs.
        PATH=${cctools}/bin:$PATH
        cp --remove-destination ${ldc}/lib/libLTO.dylib $out/lib/libLTO.dylib
        chmod u+w $out/lib/libLTO.dylib
        install_name_tool -add_rpath ${cc.cc}/lib $out/lib/libLTO.dylib
        ${darwin.sigtool}/bin/codesign -f -s - $out/lib/libLTO.dylib
        ltoFlags="--add-flags -flto-binary=$out/lib/libLTO.dylib"
      fi
    ''
    + ''
      for drv in ldc2 ldmd2; do
        rm $out/bin/$drv
        makeWrapper ${ldc}/bin/$drv $out/bin/$drv ${lib.concatStringsSep " " flags}${lib.optionalString stdenv.hostPlatform.isDarwin " $ltoFlags"}
      done
    '';
  passthru = (ldc.passthru or { }) // {
    unwrapped = ldc;
    linkCc = cc;
    inherit (ldc) src version;
  };
  meta = ldc.meta // {
    mainProgram = "ldc2";
  };
}
