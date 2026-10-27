# An LDC that also compiles and links WASI programs, one preview per triple:
# the compiler, plus a `60-wasi.conf` drop-in in its `etc/ldc2.conf/`
# directory with a section for each preview, which links against that
# preview's druntime and Phobos (./wasi-runtime.nix) through its driver
# (../wasi). The compiler's own drop-ins stay: upstream's
# `51-target-wasm-base.conf` (stack size, exception handling) and
# `55-target-wasm-naked.conf` (bare wasm without a runtime) still apply.
#
#   ldc2 -mtriple=wasm32-wasip1 app.d   # a module, runs under wasmtime
#   ldc2 -mtriple=wasm32-wasip2 app.d   # a component
#
# The drivers are wrapped with `-conf=` for the merged directory: an `ldc2`
# reached through a symlink would read the unwrapped package's configuration.
{
  lib,
  symlinkJoin,
  writeText,
  makeWrapper,
  ldc,
  # One `{ runtime, driver }` per preview.
  previews,
}:
let
  section =
    { runtime, driver }:
    let
      # `wasm32-wasi` is preview 1's older name.
      pattern =
        if lib.hasSuffix "wasip1" driver.target then
          "^wasm32-.*-wasi(p1)?$"
        else
          "^wasm32-.*-${lib.removePrefix "wasm32-" driver.target}$";
    in
    ''
      "${pattern}":
      {
          switches ~= [
              "-defaultlib=phobos2-ldc,druntime-ldc",
              // No shared druntime/Phobos on WASI, whatever `50-nix.conf` says.
              "-link-defaultlib-shared=false",
              "-gcc=${driver}/bin/${driver.target}-clang",
          ];
          lib-dirs = [
              "${runtime}/lib",
          ];
          rpath = "";
      };
    '';
  conf = writeText "60-wasi.conf" (
    ''
      // Added by dlang.nix: each WASI preview links against its own druntime
      // and Phobos through its own driver.
    ''
    + lib.concatMapStrings section previews
  );
in
symlinkJoin {
  name = "${ldc.name}-wasi";
  paths = [ ldc ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    conf=$out/etc/ldc2.conf
    rm -r $conf
    mkdir -p $conf
    cp -L ${ldc}/etc/ldc2.conf/* $conf/
    cp ${conf} $conf/60-wasi.conf

    for drv in ldc2 ldmd2; do
      rm $out/bin/$drv
      makeWrapper ${ldc}/bin/$drv $out/bin/$drv --add-flags "-conf=$conf"
    done
  '';
  passthru = (ldc.passthru or { }) // {
    inherit previews;
    unwrapped = ldc;
    inherit (ldc) src version;
  };
  meta = ldc.meta // {
    description = "${ldc.meta.description or "LDC"}, with WASI runtimes";
    mainProgram = "ldc2";
  };
}
