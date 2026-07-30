# LDC druntime + phobos cross-built for Android, from the same LDC source
# tarball as the host compiler, using `ldc-build-runtime` driving the NDK's
# CMake toolchain file. Instantiated once per target arch (aarch64, x86_64).
# The resulting static libraries are consumed by the `ldc-android` wrapper
# (see ./android.nix), which registers an `<arch>-.*-linux-android` section
# per runtime in ldc2.conf pointing `lib-dirs` here.
#
# Recipe per the LDC "Cross-compiling with LDC" / "Build D for Android" notes:
#   ldc-build-runtime --ninja \
#       --dFlags="-mtriple=aarch64--linux-android" \
#       --targetSystem="Android;Linux;UNIX" \
#       CMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
#       ANDROID_ABI=arm64-v8a ANDROID_NATIVE_API_LEVEL=21
{
  lib,
  stdenv,
  cmake,
  ninja,
  ldc,
  # NDK *root* (the directory containing build/cmake/android.toolchain.cmake and
  # toolchains/llvm/prebuilt/linux-x86_64), not the ndk-bundle store root.
  ndk,
  abi ? "arm64-v8a",
  apiLevel ? "21",
  # LLVM target triple LDC matches against the `<arch>-.*-linux-android`
  # config section. The empty vendor field (double dash) matches upstream docs.
  mtriple ? "aarch64--linux-android",
}:

let
  # "aarch64--linux-android" -> "aarch64"; "x86_64--linux-android" -> "x86_64".
  # The triples here always use the empty vendor field (double dash), so the
  # arch is everything before it.
  archTag = lib.head (lib.splitString "--" mtriple);
  buildDir = "build-android-${archTag}";
in
stdenv.mkDerivation {
  pname = "ldc-android-runtime-${archTag}";
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

    export ANDROID_NDK_ROOT=${ndk}
    export ANDROID_NDK_HOME=${ndk}

    # Static-only: the shared druntime fails to link against bionic
    # (`__tls_get_addr` undefined in rt/sections_elf_shared), and the Android
    # cross-compile path links the static runtime anyway
    # (`-link-defaultlib-shared=false`), so the shared variants are dead weight.
    ldc-build-runtime --ninja \
      --ldcSrcDir="$PWD" \
      --buildDir="$PWD/${buildDir}" \
      --dFlags="-mtriple=${mtriple}" \
      --targetSystem="Android;Linux;UNIX" \
      BUILD_SHARED_LIBS=OFF \
      CMAKE_TOOLCHAIN_FILE=${ndk}/build/cmake/android.toolchain.cmake \
      ANDROID_ABI=${abi} \
      ANDROID_NATIVE_API_LEVEL=${apiLevel}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib
    cp -v ${buildDir}/lib/*.a $out/lib/ 2>/dev/null || true
    # Some configurations also emit shared objects; ship them if present.
    cp -v ${buildDir}/lib/*.so $out/lib/ 2>/dev/null || true

    if [ -z "$(ls -A $out/lib)" ]; then
      echo "error: no runtime libraries produced in ${buildDir}/lib" >&2
      find ${buildDir} -name '*.a' -o -name '*.so' >&2 || true
      exit 1
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "LDC druntime + phobos cross-built for Android ${archTag}";
    homepage = "https://github.com/ldc-developers/ldc";
    license = with licenses; [
      bsd3
      boost
    ];
    platforms = [ "x86_64-linux" ];
  };
}
