# `ldc-android`: the host LDC, taught to cross-compile for Android
# (aarch64 for devices, x86_64 for emulator images — one wrapper serves both).
#
# It wraps the normal (host) `ldc2`/`ldmd2` with a `-conf=` override pointing at
# a config that is the host config plus one extra section per Android target.
# Each section links against its cross-built runtime (./android-runtime.nix)
# and uses the NDK clang as LDC's C compiler / linker driver (`-gcc`). The
# section regexes are disjoint, so both targets live in the same merged conf
# and the triple passed via `-mtriple=` selects the right one.
#
# Usage once on PATH (see the opt-in devShell in the sparkles repo):
#   ldc2 -mtriple=aarch64--linux-android --shared app.d c.c \
#        -L-llog -L-landroid -of=libapp.so
#   ldc2 -mtriple=x86_64--linux-android  --shared app.d c.c \
#        -L-llog -L-landroid -of=libapp.so
#
# We follow the repo's established Darwin-wrapper idiom (symlinkJoin + wrapProgram
# with `-conf=`) rather than mutating the read-only config directory: the result
# stays a *complete* ldc (its `lib/`, `ldmd2`, etc. are untouched) and only the
# two drivers gain the extra `-conf` flag.
{
  lib,
  symlinkJoin,
  makeWrapper,
  runCommand,
  ldc,
  # One entry per Android target:
  #   triplePattern — ldc2.conf section key (a regex matched against -mtriple)
  #   clangPrefix   — NDK clang basename prefix (apiLevel + "-clang" appended)
  #   runtime       — the cross-built druntime/phobos (./android-runtime.nix)
  androidRuntimes,
  # NDK root (dir containing toolchains/llvm/prebuilt/linux-x86_64).
  ndk,
  apiLevel ? "21",
}:

let
  # A section appended after the host sections. `~=` appends to the default
  # switches; `lib-dirs`/`rpath` are overwritten so the host runtime is never
  # searched for an Android link. `-link-defaultlib-shared=false` selects the
  # static druntime/phobos archives shipped by the runtime (the shared druntime
  # fails to link against bionic: `__tls_get_addr`).
  section =
    {
      triplePattern,
      clangPrefix,
      runtime,
    }:
    ''

      // ---- added by dlang.nix ldc-android (cross-compile to Android, ${clangPrefix}) ----
      "${triplePattern}":
      {
          switches ~= [
              "-defaultlib=phobos2-ldc,druntime-ldc",
              "-link-defaultlib-shared=false",
              "-gcc=${ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/${clangPrefix}${apiLevel}-clang",
          ];
          lib-dirs = [
              "${runtime}/lib",
          ];
          rpath = "";
      };
    '';

  androidSections = lib.concatStrings (map section androidRuntimes);

  # LDC's directory-based config is read by concatenating its `*.conf` files in
  # natural order; `-conf=<file>` instead reads a single file. We reproduce the
  # directory by concatenating the host drop-ins (in glob/lexical order, which
  # matches LDC's numeric ordering) and appending the Android sections.
  mergedConf = runCommand "ldc2-android.conf" { } ''
    cat ${ldc}/etc/ldc2.conf/*.conf > $out
    cat >> $out <<'LDC_ANDROID_EOF'
    ${androidSections}
    LDC_ANDROID_EOF
  '';
in
symlinkJoin {
  name = "ldc-android-${ldc.version}";
  paths = [ ldc ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    for drv in ldc2 ldmd2; do
      wrapProgram "$out/bin/$drv" --add-flags "-conf=${mergedConf}"
    done
  '';
  passthru = {
    inherit androidRuntimes mergedConf;
    # Back-compat alias: the aarch64 runtime (the first registered target).
    androidRuntime = (lib.head androidRuntimes).runtime;
    ndkRoot = ndk;
  };
  meta = ldc.meta // {
    description = "LDC configured to cross-compile for Android (aarch64 + x86_64)";
    mainProgram = "ldc2";
    platforms = [ "x86_64-linux" ];
  };
}
