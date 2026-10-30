# An LDC whose programs link the all-LLVM runtime profile (Sparkles'
# toolchain specification, TC18): compiler-rt's builtins, LLVM's libunwind and
# LLVM's libc++ in place of libgcc, libgcc_s and libstdc++, through a
# `clang-sparkles` built with them (`cc`).
#
# druntime, Phobos, libunwind and libc++ link statically, so a program loads
# one unwinder and no GCC runtime (TC19); libc++, which carries libc++abi,
# costs nothing in a program without C++. The C library stays dynamic.
#
# druntime and Phobos link statically even where a command line asks for
# the shared ones (`-link-defaultlib-shared`, as dub's unittest build types
# do): the shared libraries are built for the default profile and need
# libgcc_s, whose unwinder would then share the process with this one's.
# An `ldc2.conf` post-switch, read through `-conf`, has the last word.
#
#   ldc2 app.d cpp_part.o   # cpp_part.o compiled by the same `cc`'s c++
{
  lib,
  symlinkJoin,
  makeWrapper,
  ldc,
  cc,
}:
symlinkJoin {
  name = "${ldc.name}-llvm-runtimes";
  paths = [ ldc ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    cat > $out/etc/ldc2.conf/60-llvm-runtimes.conf <<'EOF'
    "default": {
        post-switches ~= [
            "-link-defaultlib-shared=false",
        ];
    };
    EOF
    for drv in ldc2 ldmd2; do
      rm $out/bin/$drv
      makeWrapper ${ldc}/bin/$drv $out/bin/$drv \
        --set CC ${cc}/bin/cc \
        --add-flags "-conf=$out/etc/ldc2.conf" \
        --add-flags "-link-defaultlib-shared=false -Xcc=-static-libgcc -L-l:libc++.a"
    done
  '';
  passthru = (ldc.passthru or { }) // {
    unwrapped = ldc;
    inherit cc;
    inherit (ldc) src version;
  };
  meta = ldc.meta // {
    description = "${ldc.meta.description or "LDC"}, linking LLVM's runtimes";
    mainProgram = "ldc2";
    platforms = lib.platforms.linux;
  };
}
