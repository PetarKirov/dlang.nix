# `ldc-android`: the host LDC, taught to cross-compile for Android aarch64.
#
# It wraps the normal (host) `ldc2`/`ldmd2` with a `-conf=` override pointing at
# a config that is the host config plus an extra section matching the Android
# triple. That section links against the cross-built runtime (./android-runtime.nix)
# and uses the NDK clang as LDC's C compiler / linker driver (`-gcc`).
#
# Usage once on PATH (see the opt-in devShell in the sparkles repo):
#   ldc2 -mtriple=aarch64--linux-android --shared app.d c.c \
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
  # Cross-built druntime/phobos for aarch64 Android (./android-runtime.nix).
  androidRuntime,
  # NDK root (dir containing toolchains/llvm/prebuilt/linux-x86_64).
  ndk,
  apiLevel ? "21",
}:

let
  ndkClang = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${apiLevel}-clang";

  # The Android section appended after the host sections. `~=` appends to the
  # default switches; `lib-dirs`/`rpath` are overwritten so the host runtime is
  # never searched for an Android link. `-link-defaultlib-shared=false` selects
  # the static druntime/phobos archives shipped by androidRuntime.
  androidSection = ''

    // ---- added by dlang.nix ldc-android (cross-compile to Android aarch64) ----
    "aarch64-.*-linux-android":
    {
        switches ~= [
            "-defaultlib=phobos2-ldc,druntime-ldc",
            "-link-defaultlib-shared=false",
            "-gcc=${ndkClang}",
        ];
        lib-dirs = [
            "${androidRuntime}/lib",
        ];
        rpath = "";
    };
  '';

  # LDC's directory-based config is read by concatenating its `*.conf` files in
  # natural order; `-conf=<file>` instead reads a single file. We reproduce the
  # directory by concatenating the host drop-ins (in glob/lexical order, which
  # matches LDC's numeric ordering) and appending the Android section.
  mergedConf = runCommand "ldc2-android.conf" { } ''
    cat ${ldc}/etc/ldc2.conf/*.conf > $out
    cat >> $out <<'LDC_ANDROID_EOF'
    ${androidSection}
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
    inherit androidRuntime mergedConf;
    ndkRoot = ndk;
  };
  meta = ldc.meta // {
    description = "LDC configured to cross-compile for Android aarch64";
    mainProgram = "ldc2";
    platforms = [ "x86_64-linux" ];
  };
}
