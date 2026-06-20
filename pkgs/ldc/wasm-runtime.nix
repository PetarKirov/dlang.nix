# LDC druntime + phobos cross-built for WebAssembly (wasm32-wasip2), from the same
# fork source as the host compiler (./generic.nix via `srcOverride`), using
# `ldc-build-runtime` driving CMake with the WASI sysroot + unwrapped clang. The
# static archives are consumed by the `ldc-wasm` wrapper (./wasm.nix), which adds a
# `^wasm(32|64)-` section to ldc2.conf pointing `lib-dirs` here.
#
# Mirrors the manual recipe from the LDC WASI dev shell:
#   ldc-build-runtime --ninja --targetSystem "WASI" \
#     CMAKE_C_COMPILER="$CLANG_UNWRAPPED" \
#     CMAKE_C_FLAGS="-target wasm32-wasip1 --sysroot=$WASI_SYSROOT" \
#     --dFlags="-mtriple=wasm32-wasip2" \
#     CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
{
  lib,
  stdenv,
  cmake,
  ninja,
  # The fork compiler (./generic.nix output): provides ldc-build-runtime + an
  # ldc2 that knows the wasm32-wasip2 target, and `.src` (the fork tree).
  ldc,
  # Merged wasilibc tree (libs + headers).
  wasiSysroot,
  # Unwrapped clang binary (the Nix-wrapped clang forces host header paths).
  clangUnwrapped,
  mtriple ? "wasm32-wasip2",
  cTarget ? "wasm32-wasip1",
}:

stdenv.mkDerivation {
  pname = "ldc-wasm-runtime";
  inherit (ldc) version;

  # Reuse the exact source the host compiler was built from, so the cross-built
  # runtime ABI always matches the compiler that links against it.
  src = ldc.src;

  nativeBuildInputs = [
    cmake
    ninja
    ldc
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    ldc-build-runtime --ninja \
      --ldc=${ldc}/bin/ldc2 \
      --ldcSrcDir="$PWD" \
      --buildDir="$PWD/build-wasm" \
      --dFlags="-mtriple=${mtriple}" \
      --targetSystem="WASI" \
      CMAKE_C_COMPILER=${clangUnwrapped} \
      CMAKE_C_FLAGS="-target ${cTarget} --sysroot=${wasiSysroot}" \
      CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      BUILD_SHARED_LIBS=OFF

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib
    cp -v build-wasm/lib/*.a $out/lib/

    if [ -z "$(ls -A $out/lib)" ]; then
      echo "error: no runtime libraries produced in build-wasm/lib" >&2
      find build-wasm -name '*.a' >&2 || true
      exit 1
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "LDC druntime + phobos cross-built for wasm32-wasip2";
    homepage = "https://github.com/ldc-developers/ldc";
    license = with licenses; [
      bsd3
      boost
    ];
    platforms = [ "x86_64-linux" ];
  };
}
