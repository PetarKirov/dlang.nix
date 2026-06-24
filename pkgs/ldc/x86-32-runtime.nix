# LDC druntime + phobos cross-built for 32-bit x86 (i686-linux), from the same
# LDC source tarball as the host compiler, using `ldc-build-runtime`. The
# resulting static libraries are consumed by the `ldc-x86-32` wrapper (see
# ./x86-32.nix), which registers an `i[3-6]86-.*-linux-gnu` section in
# ldc2.conf pointing `lib-dirs` here.
#
# Unlike the Android variant there is no vendor toolchain file: NixOS's
# `pkgsi686Linux.stdenv.cc` is itself a complete gcc that *natively* targets
# i686 with a 32-bit glibc (it is not a multilib `-m32` driver — passing `-m32`
# would break it). We therefore drive `ldc-build-runtime` with a plain Linux
# cross configuration:
#   ldc-build-runtime --ninja \
#       --dFlags="-mtriple=i686-pc-linux-gnu" \
#       --targetSystem="Linux;UNIX" \
#       BUILD_SHARED_LIBS=OFF \
#       CMAKE_C_COMPILER=<i686-cc> CMAKE_CXX_COMPILER=<i686-c++> \
#       CMAKE_SYSTEM_NAME=Linux CMAKE_SYSTEM_PROCESSOR=i686
{
  lib,
  stdenv,
  cmake,
  ninja,
  ldc,
  # A gcc that natively targets i686-linux with a 32-bit glibc
  # (pkgsi686Linux.stdenv.cc). Used as LDC's codegen C compiler / linker driver.
  i686cc,
  # LLVM target triple LDC matches against the `i[3-6]86-.*-linux-gnu` config
  # section. `i686-pc-linux-gnu` is the LLVM canonical form.
  mtriple ? "i686-pc-linux-gnu",
}:

stdenv.mkDerivation {
  pname = "ldc-x86-32-runtime-i686";
  inherit (ldc) version;

  # Reuse the exact source the host LDC was built from, so the cross-built
  # runtime ABI always matches the compiler that links against it.
  src = ldc.src;

  nativeBuildInputs = [
    cmake # ldc-build-runtime drives cmake under the hood
    ninja
    ldc # provides ldc-build-runtime + the host ldc2 used to codegen the runtime
  ];

  # ldc-build-runtime does the configure/build itself; skip stdenv's phases.
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # The native i686 gcc driver, used both for any C/assembly TUs in the
    # runtime and as LDC's linker driver. cc/c++ are the generic wrapper names.
    i686cc="${i686cc}/bin/cc"
    i686cxx="${i686cc}/bin/c++"

    # Static-only: the cross-link path uses `-link-defaultlib-shared=false`
    # (see ./x86-32.nix), so the shared variants are dead weight.
    # No `--cFlags=-mtriple=…`: those flags reach gcc, which rejects `-mtriple`.
    # The i686 cc already emits 32-bit code natively, so the C/asm TUs need no
    # extra target flag — only LDC's own D codegen takes `-mtriple` via --dFlags.
    ldc-build-runtime --ninja \
      --ldcSrcDir="$PWD" \
      --buildDir="$PWD/build-i686" \
      --dFlags="-mtriple=${mtriple}" \
      --targetSystem="Linux;UNIX" \
      BUILD_SHARED_LIBS=OFF \
      CMAKE_SYSTEM_NAME=Linux \
      CMAKE_SYSTEM_PROCESSOR=i686 \
      CMAKE_C_COMPILER="$i686cc" \
      CMAKE_CXX_COMPILER="$i686cxx" \
      CMAKE_ASM_COMPILER="$i686cc"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib
    cp -v build-i686/lib/*.a $out/lib/ 2>/dev/null || true
    cp -v build-i686/lib/*.so $out/lib/ 2>/dev/null || true

    if [ -z "$(ls -A $out/lib)" ]; then
      echo "error: no runtime libraries produced in build-i686/lib" >&2
      find build-i686 -name '*.a' -o -name '*.so' >&2 || true
      exit 1
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "LDC druntime + phobos cross-built for i686-linux (32-bit x86)";
    homepage = "https://github.com/ldc-developers/ldc";
    license = with licenses; [
      bsd3
      boost
    ];
    platforms = [ "x86_64-linux" ];
  };
}
