# `ldc-x86-32`: the host LDC, taught to cross-compile for 32-bit x86 (i686-linux).
#
# It wraps the normal (host) `ldc2`/`ldmd2` with a `-conf=` override pointing at
# a config that is the host config plus an extra section matching the i686 triple.
# That section links against the cross-built runtime (./x86-32-runtime.nix) and
# uses the native i686 gcc as LDC's C compiler / linker driver (`-gcc`).
#
# Usage once on PATH:
#   ldc2 -mtriple=i686-pc-linux-gnu -static app.d -of=app
#   qemu-i386 ./app
#
# We follow the repo's established wrapper idiom (symlinkJoin + wrapProgram with
# `-conf=`) rather than mutating the read-only config directory.
{
  lib,
  symlinkJoin,
  makeWrapper,
  runCommand,
  ldc,
  # Cross-built druntime/phobos for i686-linux (./x86-32-runtime.nix).
  x86_32Runtime,
  # A gcc that natively targets i686-linux with a 32-bit glibc
  # (pkgsi686Linux.stdenv.cc); LDC's `-gcc=` linker driver.
  i686cc,
  # Static 32-bit glibc (pkgsi686Linux.glibc.static), whose lib dir holds the
  # `*.a` archives needed for `-static` links (libc.a, libpthread.a, libm.a, …).
  i686GlibcStatic,
}:

let
  i686Driver = "${i686cc}/bin/cc";

  # The i686 section appended after the host sections. `~=` appends to the
  # default switches; `lib-dirs`/`rpath` are overwritten so the host runtime is
  # never searched for a 32-bit link. `-link-defaultlib-shared=false` selects
  # the static druntime/phobos archives shipped by x86_32Runtime. The static
  # glibc lib dir is put on the linker search path so `-static` links resolve
  # libc.a / libpthread.a etc.
  x86_32Section = ''

    // ---- added by dlang.nix ldc-x86-32 (cross-compile to i686-linux) ----
    "i[3-6]86-.*-linux-gnu":
    {
        switches ~= [
            "-defaultlib=phobos2-ldc,druntime-ldc",
            "-link-defaultlib-shared=false",
            "-gcc=${i686Driver}",
        ];
        lib-dirs = [
            "${x86_32Runtime}/lib",
            "${i686GlibcStatic}/lib",
        ];
        rpath = "";
    };
  '';

  mergedConf = runCommand "ldc2-x86-32.conf" { } ''
    cat ${ldc}/etc/ldc2.conf/*.conf > $out
    cat >> $out <<'LDC_X86_32_EOF'
    ${x86_32Section}
    LDC_X86_32_EOF
  '';
in
symlinkJoin {
  name = "ldc-x86-32-${ldc.version}";
  paths = [ ldc ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    for drv in ldc2 ldmd2; do
      wrapProgram "$out/bin/$drv" --add-flags "-conf=${mergedConf}"
    done
  '';
  passthru = {
    inherit x86_32Runtime mergedConf;
    inherit i686cc i686GlibcStatic;
  };
  meta = ldc.meta // {
    description = "LDC configured to cross-compile for i686-linux (32-bit x86)";
    mainProgram = "ldc2";
    platforms = [ "x86_64-linux" ];
  };
}
