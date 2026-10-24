# An LDC that also compiles and links `wasm32-wasip1` programs: the compiler,
# plus a `60-wasi.conf` drop-in in its `etc/ldc2.conf/` directory that links
# WASI programs against ./wasi-runtime.nix through wasi-sdk's driver. The
# compiler's own drop-ins stay: upstream's `51-target-wasm-base.conf` (stack
# size, exception handling) and `55-target-wasm-naked.conf` (bare wasm
# without a runtime) still apply.
#
#   ldc2 -mtriple=wasm32-wasip1 app.d   # app.wasm, runs under wasmtime
#
# The drivers are wrapped with `-conf=` for the merged directory: an `ldc2`
# reached through a symlink would read the unwrapped package's configuration.
{
  lib,
  symlinkJoin,
  makeWrapper,
  ldc,
  wasiRuntime,
  wasiSdk,
}:
symlinkJoin {
  name = "${ldc.name}-wasi";
  paths = [ ldc ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    conf=$out/etc/ldc2.conf
    rm -r $conf
    mkdir -p $conf
    cp -L ${ldc}/etc/ldc2.conf/* $conf/
    cat > $conf/60-wasi.conf <<'EOF'
    // Added by dlang.nix: WASI preview 1 programs link against druntime and
    // Phobos through wasi-sdk's driver.
    "^wasm32-.*-wasi(p1)?$":
    {
        switches ~= [
            "-defaultlib=phobos2-ldc,druntime-ldc",
            // No shared druntime/Phobos on WASI, whatever `50-nix.conf` says.
            "-link-defaultlib-shared=false",
            "-gcc=${wasiSdk.cc}",
        ];
        lib-dirs = [
            "${wasiRuntime}/lib",
        ];
        rpath = "";
    };
    EOF

    for drv in ldc2 ldmd2; do
      rm $out/bin/$drv
      makeWrapper ${ldc}/bin/$drv $out/bin/$drv --add-flags "-conf=$conf"
    done
  '';
  passthru = (ldc.passthru or { }) // {
    inherit wasiRuntime wasiSdk;
    unwrapped = ldc;
    inherit (ldc) src version;
  };
  meta = ldc.meta // {
    description = "${ldc.meta.description or "LDC"}, with a wasm32-wasip1 runtime";
    mainProgram = "ldc2";
  };
}
