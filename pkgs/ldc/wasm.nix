# `ldc-wasm`: the fork LDC, configured to compile + link `wasm32-wasip2`
# components out of the box. Wraps the fork `ldc2`/`ldmd2` (./generic.nix) with a
# `-conf=` override that adds a `^wasm(32|64)-` section linking the cross-built
# runtime (./wasm-runtime.nix) and the wasm32 compiler-rt builtins, and puts
# `wasm-component-ld` on PATH (+ `WASI_SYSROOT`) so the driver's automatic WASI
# linkage finds the linker and sysroot.
#
# Usage once on PATH:
#   ldc2 -mtriple=wasm32-wasip2 app.d -of=app.wasm   # -> a WASI component
#
# Follows the repo's `ldc-android` wrapper idiom (symlinkJoin + wrapProgram).
{
  lib,
  symlinkJoin,
  makeWrapper,
  runCommand,
  ldc,
  # Cross-built druntime/phobos for wasm (./wasm-runtime.nix).
  wasmRuntime,
  # WASI component linker (bytecodealliance/wasm-component-ld). It shells out to
  # `wasm-ld`, so lld must be on PATH too.
  wasmComponentLd,
  lld,
  # Merged wasilibc tree (libs + headers).
  wasiSysroot,
  # The wasm32 compiler-rt builtins archive (…/lib/wasi/libclang_rt.builtins-wasm32.a).
  compilerRtWasm32,
}:

let
  wasmSection = ''

    // ---- added by dlang.nix ldc-wasm (compile/link wasm32-wasip2) ----
    "^wasm(32|64)-":
    {
        switches ~= [
            "-defaultlib=phobos2-ldc,druntime-ldc",
            "-L${compilerRtWasm32}",
        ];
        lib-dirs = [
            "${wasmRuntime}/lib",
        ];
        rpath = "";
    };
  '';

  mergedConf = runCommand "ldc2-wasm.conf" { } ''
    cat ${ldc}/etc/ldc2.conf/*.conf > $out
    cat >> $out <<'LDC_WASM_EOF'
    ${wasmSection}
    LDC_WASM_EOF
  '';
in
symlinkJoin {
  name = "ldc-wasm-${ldc.version}";
  paths = [ ldc ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    for drv in ldc2 ldmd2; do
      wrapProgram "$out/bin/$drv" \
        --add-flags "-conf=${mergedConf}" \
        --prefix PATH : ${
          lib.makeBinPath [
            wasmComponentLd
            lld
          ]
        } \
        --set-default WASI_SYSROOT "${wasiSysroot}"
    done
  '';
  passthru = {
    inherit wasmRuntime mergedConf wasiSysroot;
  };
  meta = ldc.meta // {
    description = "LDC configured to compile + link wasm32-wasip2 components";
    mainProgram = "ldc2";
    platforms = [ "x86_64-linux" ];
  };
}
