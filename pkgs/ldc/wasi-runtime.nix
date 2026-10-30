# druntime and Phobos for one WASI preview, cross-built by `ldc-build-runtime`
# from the very source the compiler was built from, so the runtime's ABI is
# always the compiler's. The C sources go through the preview's driver
# (../wasi), as do the links ./with-wasi.nix sets up. Link-time-optimization
# variants (`*-lto.a`) are built beside the plain archives (Sparkles'
# toolchain specification, TCW8).
#
# `passthru.tests.runners` builds the same runtime with its unittest runners
# and runs them under wasmtime, as upstream LDC's WASI CI does
# (.github/actions/5a-wasi): the runtime test suites of TCW10.
{
  lib,
  stdenv,
  cmake,
  ninja,
  wasmtime,
  tzdata,
  # The compiler: provides `ldc-build-runtime`, the `ldc2` that compiles the
  # runtime, and `.src`.
  ldc,
  # The preview's driver from ../wasi; its `passthru.target` is the triple.
  driver,
  # Provides `llvm-ar` / `llvm-ranlib` for the archives.
  llvm,
}:
let
  inherit (driver) target;

  # The test runners, each with the modules whose unittests fail on WASI,
  # space-separated and sorted (Sparkles' toolchain specification, TCW10).
  # The LDC folds compile-time `real` in the target's format on any host
  # (TCW11), so the lists do not depend on the build host.
  runners = {
    druntime-test-runner = "";
    druntime-test-runner-debug = "";
    phobos2-test-runner = "";
    phobos2-test-runner-debug = "";
  };

  build =
    { testRunners }:
    stdenv.mkDerivation {
      pname = "ldc-runtime-${target}" + lib.optionalString testRunners "-tests";
      inherit (ldc) version src;

      nativeBuildInputs = [
        cmake
        ninja
      ]
      ++ lib.optional testRunners wasmtime;

      dontConfigure = true;
      # Wasm archives: the host `strip` has nothing to do with them.
      dontStrip = true;

      buildPhase = ''
        runHook preBuild

        ${ldc}/bin/ldc-build-runtime --ninja \
          --ldc=${ldc}/bin/ldc2 \
          --ldcSrcDir="$PWD" \
          --buildDir="$PWD/build-${target}" \
          --dFlags="-mtriple=${target}" \
          --targetSystem=WASI \
          CMAKE_SYSTEM_NAME=WASI \
          CMAKE_C_COMPILER=${driver}/bin/${target}-clang \
          CMAKE_CXX_COMPILER=${driver}/bin/${target}-clang++ \
          CMAKE_AR=${llvm}/bin/llvm-ar \
          CMAKE_RANLIB=${llvm}/bin/llvm-ranlib \
          CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
          BUILD_SHARED_LIBS=OFF \
          BUILD_LTO_LIBS=ON
      ''
      + lib.optionalString testRunners ''
        ninja -C build-${target} ${lib.concatStringsSep " " (lib.attrNames runners)}
      ''
      + ''

        runHook postBuild
      '';

      doCheck = testRunners;
      checkPhase = ''
        runHook preCheck
        cd build-${target}
        export WASMTIME_BACKTRACE_DETAILS=1
        # wasmtime keeps a compilation cache under $HOME.
        export HOME=$TMPDIR
        # Phobos' tests write temporary files under `/tmp`, read `$HOME`, and
        # load time zones from `$TZDIR`: each runner gets a scratch root and
        # the time-zone database, as upstream LDC's WASI CI grants them.
        mkdir -p "$TMPDIR/wasi-root/tmp"
        # A runner exits 1 when a module fails, and otherwise only when it
        # traps. Any failure but the known ones fails the check, and so does
        # a known failure that now passes.
        while read -r runner knownFailures; do
          echo "== $runner"
          status=0
          wasmtime run -W exceptions=y \
            --dir "$TMPDIR/wasi-root::/" \
            --dir ${tzdata}/share/zoneinfo::/tz \
            --env TZDIR=/tz/ \
            --env HOME=/tmp \
            -S inherit-network \
            "$runner" < /dev/null > "$TMPDIR/$runner.log" || status=$?
          cat "$TMPDIR/$runner.log"
          if [ "$status" -gt 1 ]; then
            echo "$runner trapped (exit status $status)"
            exit 1
          fi
          failed=$(sed -n 's/^\*\*\*\*\*\* FAIL [^ ]* //p' "$TMPDIR/$runner.log" | sort | xargs)
          if [ "$failed" != "$knownFailures" ]; then
            echo "$runner: modules [$failed] failed, [$knownFailures] expected"
            exit 1
          fi
        done <<'EOF'
        ${lib.concatStrings (lib.mapAttrsToList (runner: failures: "${runner} ${failures}\n") runners)}EOF
        cd ..
        runHook postCheck
      '';

      installPhase = ''
        runHook preInstall
      ''
      + (
        if testRunners then
          ''
            touch $out
          ''
        else
          ''
            install -Dm644 -t $out/lib build-${target}/lib/*.a
          ''
      )
      + ''
        runHook postInstall
      '';

      passthru = {
        inherit target;
        inherit (driver.passthru) buildStatus;
      }
      // lib.optionalAttrs (!testRunners) {
        tests.runners = build { testRunners = true; };
      };

      meta = {
        description = "LDC's druntime and Phobos for ${target}";
        homepage = "https://github.com/ldc-developers/ldc";
        license = with lib.licenses; [
          bsd3
          boost
        ];
        inherit (ldc.meta) platforms;
      };
    };
in
build { testRunners = false; }
