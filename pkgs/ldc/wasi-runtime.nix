# druntime and Phobos for a WASI target, cross-built by `ldc-build-runtime`
# from the very source the compiler was built from, so the runtime's ABI is
# always the compiler's. The C sources and the test runners' links go through
# wasi-sdk's driver (./wasi-sdk.nix), as in upstream LDC's WASI CI
# (.github/actions/5a-wasi).
#
# The static archives land in `$out/lib`; ./with-wasi.nix points a
# `ldc2.conf` section at them.
{
  lib,
  stdenv,
  cmake,
  ninja,
  # The compiler: provides `ldc-build-runtime`, the `ldc2` that compiles the
  # runtime, and `.src`.
  ldc,
  # ./wasi-sdk.nix
  wasiSdk,
  # Provides `llvm-ar` / `llvm-ranlib` for the archives.
  llvm,
  triple ? "wasm32-unknown-wasip1",
}:
stdenv.mkDerivation {
  pname = "ldc-runtime-${triple}";
  inherit (ldc) version src;

  nativeBuildInputs = [
    cmake
    ninja
  ];

  dontConfigure = true;
  # Wasm archives: the host `strip` has nothing to do with them.
  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    ${ldc}/bin/ldc-build-runtime --ninja \
      --ldc=${ldc}/bin/ldc2 \
      --ldcSrcDir="$PWD" \
      --buildDir="$PWD/build-${triple}" \
      --dFlags="-mtriple=${triple}" \
      --targetSystem=WASI \
      CMAKE_SYSTEM_NAME=WASI \
      CMAKE_C_COMPILER=${wasiSdk.cc} \
      CMAKE_CXX_COMPILER=${wasiSdk.cxx} \
      CMAKE_AR=${llvm}/bin/llvm-ar \
      CMAKE_RANLIB=${llvm}/bin/llvm-ranlib \
      CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      BUILD_SHARED_LIBS=OFF

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/lib build-${triple}/lib/*.a
    runHook postInstall
  '';

  passthru.buildStatus = {
    build = true;
    check = false;
  };

  meta = {
    description = "LDC's druntime and Phobos for ${triple}";
    homepage = "https://github.com/ldc-developers/ldc";
    license = with lib.licenses; [
      bsd3
      boost
    ];
    inherit (ldc.meta) platforms;
  };
}
