# Tests of the toolchain packages that Nix runs (Sparkles' toolchain
# specification, TC22), exposed as each package's `passthru.tests`:
#
# - `clang`: `clang-sparkles` compiles and runs C, C++20 and, on macOS,
#   Objective-C.
# - `runtimes`: the compiler-rt runtimes LDC ships, through LDC and through
#   clang: AddressSanitizer reports a heap overflow, UBSan an overflow,
#   `-fprofile-instr-generate` writes a profile that `llvm-profdata` merges,
#   and a libFuzzer target runs; on Linux also ThreadSanitizer, MemorySanitizer
#   and XRay.
# - `ldc`: LDC rebuilt with its check phase: the lit tests of the directories
#   that cover the fork's targets and runtimes, and the druntime and Phobos
#   test runners.
{
  lib,
  stdenv,
  runCommand,
  clangStdenv,
  ldc,
  llvmTools,
  python3,
  spirv-tools,
  runtimeShell,
}:
let
  inherit (stdenv.hostPlatform) isDarwin isLinux;
  cc = clangStdenv.cc;
in
{
  clang =
    runCommand "clang-sparkles-test"
      {
        nativeBuildInputs = [ cc ];
      }
      (
        ''
          cat > hello.c <<'EOF'
          #include <stdio.h>
          int main(void) { puts("c ok"); return 0; }
          EOF
          cat > hello.cpp <<'EOF'
          #include <format>
          #include <iostream>
          #include <ranges>
          #include <vector>
          int main() {
            std::vector v{1, 2, 3};
            auto sum = 0;
            for (int x : v | std::views::transform([](int i) { return i * i; })) sum += x;
            std::cout << std::format("c++ ok {}", sum) << '\n';
          }
          EOF
          cc -O2 hello.c -o hello-c && ./hello-c | grep -qx 'c ok'
          c++ -std=c++20 -O2 hello.cpp -o hello-cpp && ./hello-cpp | grep -qx 'c++ ok 14'
          cc --version | grep -q 'clang version ${lib.versions.major cc.version}'
        ''
        + lib.optionalString isDarwin ''
          cat > hello.m <<'EOF'
          #import <Foundation/Foundation.h>
          int main(void) { @autoreleasepool { NSLog(@"objc ok"); } return 0; }
          EOF
          cc -fobjc-arc hello.m -framework Foundation -o hello-m && ./hello-m 2>&1 | grep -q 'objc ok'
        ''
        + ''
          touch $out
        ''
      );

  runtimes =
    runCommand "ldc-runtimes-test"
      {
        nativeBuildInputs = [
          ldc
          cc
          llvmTools
        ];
      }
      (
        ''
          export HOME=$TMPDIR
          # `_FORTIFY_SOURCE` replaces the checked libc calls ASan intercepts, so
          # an overflow goes unreported; sanitizer builds turn it off. (Setting
          # `hardeningDisable` instead re-enables arm64-only flags on x86_64.)
          export NIX_HARDENING_ENABLE=$(printf "%s\n" $NIX_HARDENING_ENABLE | grep -v fortify | tr "\n" " ")
          expect_report() { # <log> <pattern>
            grep -q "$2" "$1" || { echo "== $1:"; cat "$1"; echo "missing in $1: $2"; exit 1; }
          }

          # malloc'd memory: the GC heap is not instrumented, and a write past a
          # GC array lands inside its rounded-up block.
          cat > overflow.d <<'EOF'
          import core.stdc.stdlib : free, malloc;
          void main() {
              auto p = cast(int*) malloc(4 * int.sizeof);
              p[4] = 1;
              free(p);
          }
          EOF
          ldc2 -g -fsanitize=address overflow.d -of=asan-d
          ./asan-d 2> asan-d.log || echo "exit status $?" >> asan-d.log
          expect_report asan-d.log 'heap-buffer-overflow'

          cat > overflow.c <<'EOF'
          #include <stdlib.h>
          int main(void) { int *p = malloc(4 * sizeof *p); p[4] = 1; free(p); return 0; }
          EOF
          cc -g -fsanitize=address overflow.c -o asan-c
          ./asan-c 2> asan-c.log || echo "exit status $?" >> asan-c.log
          expect_report asan-c.log 'heap-buffer-overflow'

          # A shift, not a signed overflow: the wrapper's `strictoverflow` hardening
          # makes signed overflow defined.
          cat > ubsan.c <<'EOF'
          int main(int argc, char **argv) { return 1 << (argc + 31); }
          EOF
          cc -fsanitize=undefined ubsan.c -o ubsan-c
          ./ubsan-c 2> ubsan-c.log || echo "exit status $?" >> ubsan-c.log
          expect_report ubsan-c.log 'shift exponent'

          cat > prof.d <<'EOF'
          int f(int x) { return x > 2 ? x * 2 : x + 1; }
          void main() { foreach (i; 0 .. 10) cast(void) f(i); }
          EOF
          ldc2 -fprofile-instr-generate=prof.profraw prof.d -of=prof-d
          ./prof-d
          llvm-profdata merge -o prof.profdata prof.profraw
          llvm-profdata show prof.profdata | grep -q 'Total functions'

          cat > fuzz.d <<'EOF'
          extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) {
              return 0;
          }
          EOF
          ldc2 -fsanitize=fuzzer fuzz.d -of=fuzz-d
          ./fuzz-d -runs=200 2> fuzz-d.log
          expect_report fuzz-d.log 'Done 200 runs'
        ''
        + lib.optionalString isLinux ''
          cat > race.d <<'EOF'
          import core.thread;
          __gshared int counter;
          void main() {
              auto t = new Thread({ foreach (i; 0 .. 1000) ++counter; });
              t.start();
              foreach (i; 0 .. 1000) ++counter;
              t.join();
          }
          EOF
          # druntime and Phobos static: ThreadSanitizer does not work across the
          # shared ones (no report outside the sandbox, a crash inside it).
          ldc2 -g -fsanitize=thread -link-defaultlib-shared=false race.d -of=tsan-d
          ./tsan-d 2> tsan-d.log || echo "exit status $?" >> tsan-d.log
          expect_report tsan-d.log 'data race'

          cat > uninit.c <<'EOF'
          #include <stdlib.h>
          int main(void) { int *p = malloc(sizeof *p); int r = *p ? 1 : 0; free(p); return r; }
          EOF
          cc -fsanitize=memory -g uninit.c -o msan-c
          ./msan-c 2> msan-c.log || echo "exit status $?" >> msan-c.log
          expect_report msan-c.log 'use-of-uninitialized-value'

          cat > xray.d <<'EOF'
          int work(int x) { int s; foreach (i; 0 .. x) s += i; return s; }
          void main() { foreach (i; 0 .. 100) cast(void) work(i); }
          EOF
          ldc2 -fxray-instrument -fxray-instruction-threshold=1 xray.d -of=xray-d
          XRAY_OPTIONS="patch_premain=true xray_mode=xray-basic verbosity=1" ./xray-d 2> xray-d.log
          ls xray-log.xray-d.* > /dev/null
        ''
        + ''
          touch $out
        ''
      );

  ldc = ldc.overrideAttrs (old: {
    pname = "${old.pname}-checked";
    # druntime's profile test runs its recipes with `/bin/bash`.
    postPatch = (old.postPatch or "") + ''
      substituteInPlace runtime/druntime/test/profile/Makefile \
        --replace-fail "SHELL=/bin/bash" "SHELL=${runtimeShell}"
    '';
    doCheck = true;
    # Known failures, each a FileCheck pattern written for the LLVM releases
    # upstream LDC tests against, where LLVM main prints or optimizes the
    # same program differently. Listed in Sparkles'
    # docs/specs/toolchain/testing.md; a listed test that passes is an
    # unexpected pass, which fails the check, so the list only shrinks.
    LIT_XFAIL = lib.concatStringsSep ";" [
      # Constant GEPs into the counter arrays print as `i8` offsets.
      "PGO/allstatementtypes.d"
      "PGO/branching_switch.d"
      "PGO/break.d"
      "PGO/exceptions.d"
      "PGO/functions.d"
      # The profile summary's metadata fields changed.
      "PGO/summary.d"
      # `module asm` prints its string on the next line.
      "codegen/casm.i"
      # Different instruction order and devirtualization at -O.
      "codegen/devirtualization_assumevtable.d"
      "codegen/int128.d"
    ];
    # `spirv-dis` for the Vulkan code-generation tests.
    nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [
      python3
      spirv-tools
    ];
    # The lit directories that cover the fork's targets, instrumentation and
    # runtimes, then druntime's and Phobos' own unittests. Known failures are
    # listed, per test, in Sparkles' docs/specs/toolchain/testing.md.
    checkPhase = ''
      runHook preCheck
      # lit puts LLVM's tool directory, with its raw clang, on PATH; link through
      # the wrapped one instead (tests/lit.site.cfg passes CC through).
      export CC=${clangStdenv.cc}/bin/cc
      ninja -j$NIX_BUILD_CORES all-test-runners
      (cd tests && python3 runlit.py -v codegen driver instrument linking sanitizers PGO)
      # std.datetime.timezone: under the test runner every zone resolves to
      # `/<name>`, though a program built the same way finds it; cause not
      # yet found (Sparkles' docs/specs/toolchain/testing.md).
      ctest -j$NIX_BUILD_CORES --output-on-failure \
        -E "ldc2-unittest|lit-tests|dmd-testsuite|std\.datetime\.timezone"
      runHook postCheck
    '';
    # The check build is a test, not a package: nothing references it.
    postInstall = (old.postInstall or "") + ''
      rm -rf $out/*
      touch $out/passed
    '';
    disallowedReferences = [ ];
  });
}
