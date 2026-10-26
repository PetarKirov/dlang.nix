{ inputs, lib, ... }:
let
  inherit (lib) optionalAttrs;
in
{
  imports = [ inputs.flake-parts.flakeModules.easyOverlay ];

  perSystem =
    {
      self',
      pkgs,
      system,
      ...
    }:
    let
      inherit (import ../lib/version-catalog.nix { inherit lib pkgs self'; }) genPkgVersions;

      # Android NDK cross-compilation toolchain. Opt-in: it pulls in the
      # *unfree* Android SDK NDK, so it is kept out of the default package set
      # and only materialises when `ldc-android` is built explicitly.
      #
      # The build hosts it exists on are the hosts the NDK ships a prebuilt
      # toolchain for, keyed by the directory name the NDK files it under
      # (`toolchains/llvm/prebuilt/<tag>`). The macOS toolchain is one
      # universal (x86_64 + arm64) build, so both Mac hosts share the
      # `darwin-x86_64` tag and run it natively. There is no Linux arm64 NDK,
      # so `aarch64-linux` has no entry: the absence is the answer, and
      # everything downstream reads it from whether `ldc-android` exists.
      ndkHostTag =
        {
          x86_64-linux = "linux-x86_64";
          x86_64-darwin = "darwin-x86_64";
          aarch64-darwin = "darwin-x86_64";
        }
        .${system} or null;
      androidPkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
      ndkBundle = (androidPkgs.androidenv.composeAndroidPackages { includeNDK = true; }).ndk-bundle;
      ndkRoot = "${ndkBundle}/libexec/android-sdk/ndk/${ndkBundle.version}";
      # The Android compiler is `ldc-vulkan`, the PetarKirov/ldc fork every
      # other sparkles target builds with: one LDC and one LLVM for the host,
      # the shaders, WASI and Android. The fork also carries Bionic fixes
      # (the x86 TLS range, ldc#5311).
      mkAndroidRuntime =
        args:
        pkgs.callPackage ./ldc/android-runtime.nix (
          {
            ldc = vulkanPackages.ldc-vulkan;
            ndk = ndkRoot;
          }
          // args
        );
      # aarch64 = physical devices; x86_64 = emulator system images.
      ldcAndroidRuntimeAarch64 = mkAndroidRuntime { };
      ldcAndroidRuntimeX86_64 = mkAndroidRuntime {
        abi = "x86_64";
        mtriple = "x86_64--linux-android";
      };
      androidPackages = {
        # Back-compat alias for the original single-target attr name.
        ldc-android-runtime = ldcAndroidRuntimeAarch64;
        ldc-android-runtime-aarch64 = ldcAndroidRuntimeAarch64;
        ldc-android-runtime-x86_64 = ldcAndroidRuntimeX86_64;
        ldc-android = pkgs.callPackage ./ldc/android.nix {
          ldc = vulkanPackages.ldc-vulkan;
          androidRuntimes = [
            {
              triplePattern = "aarch64-.*-linux-android";
              clangPrefix = "aarch64-linux-android";
              runtime = ldcAndroidRuntimeAarch64;
            }
            {
              triplePattern = "x86_64-.*-linux-android";
              clangPrefix = "x86_64-linux-android";
              runtime = ldcAndroidRuntimeX86_64;
            }
          ];
          ndk = ndkRoot;
          inherit ndkHostTag;
        };
      };

      # 32-bit x86 (i686-linux) cross-compilation toolchain. Opt-in and
      # x86_64-linux-only. NixOS has no multilib, so we drive the runtime build
      # and the wrapper's `-gcc=` with `pkgsi686Linux.stdenv.cc` — a gcc that
      # natively targets i686 with a 32-bit glibc — and link the test programs
      # static against `pkgsi686Linux.glibc.static` so qemu-i386 can run them
      # without a 32-bit dynamic loader.
      i686cc = pkgs.pkgsi686Linux.stdenv.cc;
      i686GlibcStatic = pkgs.pkgsi686Linux.glibc.static;
      ldcX86_32Runtime = pkgs.callPackage ./ldc/x86-32-runtime.nix {
        ldc = self'.packages.ldc;
        inherit i686cc;
      };
      x86_32Packages = {
        ldc-x86-32-runtime = ldcX86_32Runtime;
        ldc-x86-32 = pkgs.callPackage ./ldc/x86-32.nix {
          ldc = self'.packages.ldc;
          x86_32Runtime = ldcX86_32Runtime;
          inherit i686cc i686GlibcStatic;
        };
      };

      # ---- Vulkan / SPIR-V shaders (dcompute) — Linux and macOS ----
      # LDC master + ldc-developers/ldc#5132 (dcompute's Vulkan compute target)
      # + graphics shader stages (`@vertex`, `@fragment`, `@input`/`@uniform`,
      # `@builtin`, `Sampler2D`),
      # against LLVM main with the SPIR-V backend (./llvm-spirv). Consumed by
      # sparkles' `shader-compile`, which turns single-source D shaders into
      # SPIR-V and, via spirv-cross, GLSL. Opt-in and heavy (LLVM from source).
      llvmSpirvVulkan = pkgs.callPackage ./llvm-spirv {
        src = inputs.llvm-sparkles;
        version =
          let
            d = inputs.llvm-sparkles.lastModifiedDate;
          in
          "24.0.0-unstable-${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}";
      };

      # PetarKirov/ldc `sparkles/main` (the `ldc-sparkles` input): the
      # Vulkan-shaders branch on LDC master, which also carries upstream's
      # WASI support. A flake input, so a consumer can point it at a checkout
      # with `--override-input`.
      ldcVulkanSrc = inputs.ldc-sparkles;

      vulkanPackages = {
        llvm-spirv-vulkan = llvmSpirvVulkan;
        # C and C++ on the same clang and LLVM, without rebuilding them.
        clang-sparkles = pkgs.callPackage ./llvm-spirv/clang.nix {
          llvm = llvmSpirvVulkan;
          compiler-rt = pkgs.llvmPackages_20.compiler-rt;
        };
        ldc-vulkan =
          (pkgs.callPackage
            (import ./ldc/generic.nix {
              version = "1.43.0-sparkles";
              srcOverride = ldcVulkanSrc;
              # The fork's lit tests need an LLVM with FileCheck and the
              # spirv-tools; the release test suite assumes a tarball layout.
              checkOverride = false;
              llvmPackagesOverride = {
                llvm = llvmSpirvVulkan;
                lld = llvmSpirvVulkan;
              };
            })
            {
              # The upstream binary release, as the version catalog bootstraps
              # with: the source-built `ldc`'s config links `ldc_rt.dso.o` a second
              # time into LDC's own executables (duplicate `rt.dso` symbols).
              hostDCompiler = self'.packages.ldc-bootstrap;
            }
          ).overrideAttrs
            (
              old:
              {
                # The bootstrap compiler's druntime asserts bake `__FILE__` paths
                # into LDC's own D code: dead strings, but enough to keep the
                # ~470 MiB bootstrap in the closure of every shader build (the
                # same leak `dmd` had). Scrub, and assert it stays gone.
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.removeReferencesTo ];
                preFixup = (old.preFixup or "") + ''
                  find "$out" -type f -exec remove-references-to -t ${self'.packages.ldc-bootstrap} '{}' +
                '';
                disallowedReferences = (old.disallowedReferences or [ ]) ++ [
                  self'.packages.ldc-bootstrap
                ];
              }
              // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
                # The LLVM install ships clang (the WASI C driver), and it is on
                # PATH here as `llvmPackages.llvm.dev`. Darwin's stdenv names its
                # compilers `clang`/`clang++`, so CMake would find that unwrapped
                # clang, which has no SDK or libc++ headers ('new' file not
                # found), instead of stdenv's wrapper. Name the wrapper.
                cmakeFlags = (old.cmakeFlags or [ ]) ++ [
                  "-DCMAKE_C_COMPILER=${pkgs.stdenv.cc}/bin/cc"
                  "-DCMAKE_CXX_COMPILER=${pkgs.stdenv.cc}/bin/c++"
                ];
              }
            );
      };

      # ---- The same compiler for WASI (wasm32-wasip1) — Linux and macOS ----
      # `ldc-sparkles` is `ldc-vulkan` plus a druntime/Phobos cross-built for
      # `wasm32-wasip1` from its own source, linked through wasi-sdk's sysroot:
      # one compiler for the host, Vulkan shaders and WASI.
      wasiSdk = pkgs.callPackage ./ldc/wasi-sdk.nix { llvm = llvmSpirvVulkan; };

      ldcSparklesWasiRuntime = pkgs.callPackage ./ldc/wasi-runtime.nix {
        ldc = vulkanPackages.ldc-vulkan;
        llvm = llvmSpirvVulkan;
        inherit wasiSdk;
      };

      sparklesPackages = {
        wasi-sdk = wasiSdk;
        ldc-sparkles-wasi-runtime = ldcSparklesWasiRuntime;
        ldc-sparkles = pkgs.callPackage ./ldc/with-wasi.nix {
          ldc = vulkanPackages.ldc-vulkan;
          wasiRuntime = ldcSparklesWasiRuntime;
          inherit wasiSdk;
        };
      };
    in
    {
      overlayAttrs = self'.packages;
      legacyPackages =
        { }
        // (genPkgVersions "dmd").hierarchical
        // (genPkgVersions "ldc").hierarchical
        // (genPkgVersions "dub").hierarchical;

      packages = {
        # NOTE: This is only the default. The bootstrap compiler in the
        # version catalog will override this.
        ldc-bootstrap = self'.packages."ldc-binary-1_42_0";
        ldc = self'.packages."ldc-1_42_0";

        # DUB is released alongside DMD. When DMD 2.112.0 shipped, upstream
        # appears to have forgotten to bump DUB from 1.42.0-beta.1 to the
        # final 1.42.0 tag, so the newest released DUB is still this beta.
        # Switch to "dub-1_42_0" once upstream tags the stable release.
        dub = self'.packages."dub-1_42_0-beta_1";
      }
      // (genPkgVersions "ldc").flattened "binary"
      // (genPkgVersions "ldc").flattened "source"
      // (genPkgVersions "dub").flattened "source"
      // optionalAttrs pkgs.hostPlatform.isx86 (
        {
          dmd-bootstrap = self'.packages."dmd-binary-2_098_0";
          dmd = self'.packages."dmd-2_112_0";
        }
        // (genPkgVersions "dmd").flattened "binary"
        // (genPkgVersions "dmd").flattened "source"
      )
      // optionalAttrs (ndkHostTag != null) androidPackages
      // optionalAttrs (system == "x86_64-linux") x86_32Packages
      // optionalAttrs (pkgs.hostPlatform.isLinux || pkgs.hostPlatform.isDarwin) (
        vulkanPackages // sparklesPackages
      );
    };
}
