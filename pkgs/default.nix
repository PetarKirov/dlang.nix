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

      # The install cut into what builds read (`dev`) and what a compiler
      # needs at run time (`clang`).
      llvmViews = pkgs.callPackage ./llvm-spirv/views.nix { llvm = llvmSpirvVulkan; };

      # lld with its ELF driver behind the bintools wrapper (Linux). The clang
      # wrappers take its bintools, so `-fuse-ld=lld` sets RUNPATHs.
      lldSparkles = pkgs.callPackage ./llvm-spirv/lld.nix { lld = llvmViews.lld; };
      clangBintools = optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        inherit (lldSparkles) bintools;
      };

      # compiler-rt is built by clang, so the wrapper comes twice: first with
      # nixpkgs' compiler-rt on Darwin (see ./llvm-spirv/clang.nix), then with
      # the fork's.
      clangSparklesBootstrap = pkgs.callPackage ./llvm-spirv/clang.nix (
        clangBintools
        // {
          cc = llvmViews.clang;
          compiler-rt = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.llvmPackages_20.compiler-rt else null;
        }
      );
      compilerRtSparkles = pkgs.callPackage ./llvm-spirv/compiler-rt.nix {
        stdenv = pkgs.overrideCC pkgs.stdenv clangSparklesBootstrap;
        src = inputs.llvm-sparkles;
        inherit (llvmSpirvVulkan) version;
      };
      clangSparkles = pkgs.callPackage ./llvm-spirv/clang.nix (
        clangBintools
        // {
          cc = llvmViews.clang;
          compiler-rt = compilerRtSparkles;
        }
      );
      clangStdenvSparkles = pkgs.overrideCC pkgs.stdenv clangSparkles;

      # LLVM's libunwind and libc++ for the all-LLVM runtime profile (TC18).
      llvmRuntimesSparkles = pkgs.callPackage ./llvm-spirv/llvm-runtimes.nix {
        stdenv = clangStdenvSparkles;
        src = inputs.llvm-sparkles;
        inherit (llvmSpirvVulkan) version;
      };

      # TC22: the tests Nix runs for the toolchain (./llvm-spirv/tests.nix), as
      # `passthru.tests` and as flake checks.
      toolchainTests =
        ldc:
        pkgs.callPackage ./llvm-spirv/tests.nix {
          clangStdenv = clangStdenvSparkles;
          inherit ldc;
          llvmTools = llvmViews.clang;
        };
      withToolchainTests =
        ldc:
        ldc.overrideAttrs (old: {
          passthru = old.passthru // {
            tests = toolchainTests ldc;
          };
        });

      vulkanPackages = {
        llvm-spirv-vulkan = llvmSpirvVulkan;
        llvm-spirv-vulkan-dev = llvmViews.dev;
        clang-sparkles-unwrapped = llvmViews.clang;
        compiler-rt-sparkles = compilerRtSparkles;
        # C and C++ on the same clang and LLVM as LDC.
        clang-sparkles = clangSparkles.overrideAttrs (old: {
          passthru = old.passthru // {
            tests.clang = (toolchainTests null).clang;
          };
        });
        ldc-vulkan = withToolchainTests (
          pkgs.callPackage ./ldc/with-link-cc.nix {
            cc = clangSparkles;
            ldc =
              (pkgs.callPackage
                (import ./ldc/generic.nix {
                  version = "1.43.0-sparkles";
                  srcOverride = ldcVulkanSrc;
                  # The fork's lit tests run as `passthru.tests`; the release test
                  # suite assumes a tarball layout.
                  checkOverride = false;
                  # The view without compiler drivers: CMake finds the stdenv's
                  # wrapped clang, never the install's raw one.
                  llvmPackagesOverride = {
                    llvm.dev = llvmViews.dev;
                    lld.dev = llvmViews.dev;
                  };
                  wrapperCc = clangSparkles;
                  # ./ldc/with-link-cc.nix wraps it, so `.unwrapped` carries no
                  # link compiler.
                  wrapLinkCc = false;
                })
                {
                  # LDC's own C++ by its own clang.
                  stdenv = clangStdenvSparkles;
                  # The upstream binary release, as the version catalog bootstraps
                  # with: the source-built `ldc`'s config links `ldc_rt.dso.o` a second
                  # time into LDC's own executables (duplicate `rt.dso` symbols).
                  hostDCompiler = self'.packages.ldc-bootstrap;
                }
              ).overrideAttrs
                (
                  old:
                  {
                    cmakeFlags =
                      # generic.nix sets the runtime's `D_FLAGS`, which replaces LDC's
                      # own (`-w -de -preview=dip1000 -preview=dtorfields
                      # -preview=fieldwise`): druntime and Phobos then build without
                      # the previews upstream ships them with, and Phobos' unittests
                      # do not compile. `D_EXTRA_FLAGS` adds to them instead.
                      (map (lib.replaceStrings [ "-D D_FLAGS=" ] [ "-D D_EXTRA_FLAGS=" ]) (old.cmakeFlags or [ ]))
                      ++ [
                        # LLVM's tools share `libLLVM`, but LDC links the static
                        # libraries, keeping LLVM out of its runtime closure.
                        "-DLLVM_IS_SHARED=OFF"
                        # Compile-time `real` in the target's format on any host: a
                        # quadruple-precision target (WASI, AArch64 Linux, Android)
                        # folds exactly on x86_64 and macOS hosts too (TCW11).
                        "-DLDC_REAL_APFLOAT=ON"
                        # The fork's runtimes, copied into LDC's `lib/` as
                        # `libldc_rt.*` (ASan, LSan, MSan, TSan, profile, libFuzzer,
                        # XRay, builtins).
                        "-DCOMPILER_RT_BASE_DIR=${compilerRtSparkles}/lib/clang"
                      ]
                      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
                        "-DCOMPILER_RT_LIBDIR_OS=linux"
                        "-DLDC_INSTALL_LLVM_RUNTIME_LIBS_ARCH=${pkgs.stdenv.hostPlatform.parsed.cpu.name}"
                      ];
                  }
                  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
                    # generic.nix scrubs the bootstrap compiler's `__FILE__` strings
                    # on ELF only; on Darwin this build does, and the fixup phase
                    # signs the result again.
                    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                      pkgs.removeReferencesTo
                      pkgs.darwin.autoSignDarwinBinariesHook
                    ];
                    preFixup = (old.preFixup or "") + ''
                      find "$out" -type f -exec remove-references-to -t ${self'.packages.ldc-bootstrap} '{}' +
                      # LLVM's libLTO.dylib, which LDC copies for ld64's LTO, links
                      # @rpath/libLLVM.*.dylib, and LDC's lib/ has no libLLVM. The clang
                      # view has it, and is in the closure anyway as the link compiler.
                      install_name_tool -add_rpath ${llvmViews.clang}/lib $out/lib/libLTO.dylib
                    '';
                    disallowedReferences = (old.disallowedReferences or [ ]) ++ [
                      self'.packages.ldc-bootstrap
                    ];
                  }
                );
          }
        );
      };

      # ---- The same compiler for WASI — Linux and macOS ----
      # WASI built from source (./wasi): for each preview a sysroot and a
      # driver, `wasm32-wasipN-clang`, whose passthru has the sysroot,
      # resource directory and builtins; and LDC's druntime and Phobos for
      # it (./ldc/wasi-runtime.nix). `ldc-sparkles` is `ldc-vulkan` with the
      # production previews, 1 and 2, one `ldc2.conf` section each: one
      # compiler for the host, Vulkan shaders and WASI. Preview 3 is
      # experimental (Sparkles' toolchain specification, TCW2), so only
      # `ldc-sparkles-wasip3-experimental` carries it.
      wasiPreviews = pkgs.callPackages ./wasi {
        clang = llvmViews.clang;
        llvmSrc = inputs.llvm-sparkles;
      };
      wasiRuntimes = lib.mapAttrs (
        _: driver:
        pkgs.callPackage ./ldc/wasi-runtime.nix {
          ldc = vulkanPackages.ldc-vulkan;
          llvm = llvmViews.clang;
          inherit driver;
        }
      ) wasiPreviews;
      withWasi =
        names:
        pkgs.callPackage ./ldc/with-wasi.nix {
          ldc = vulkanPackages.ldc-vulkan;
          previews = map (name: {
            driver = wasiPreviews.${name};
            runtime = wasiRuntimes.${name};
          }) names;
        };

      # The all-LLVM runtime profile (TC18), on Linux; on macOS the system's
      # C++ library and unwinder already are LLVM's.
      llvmRuntimePackages = rec {
        llvm-runtimes-sparkles = llvmRuntimesSparkles;
        clang-sparkles-llvm-runtimes = pkgs.callPackage ./llvm-spirv/clang.nix (
          clangBintools
          // {
            cc = llvmViews.clang;
            compiler-rt = compilerRtSparkles;
            llvm-runtimes = llvmRuntimesSparkles;
          }
        );
        ldc-vulkan-llvm-runtimes = pkgs.callPackage ./ldc/with-llvm-runtimes.nix {
          ldc = vulkanPackages.ldc-vulkan;
          cc = clang-sparkles-llvm-runtimes;
        };
      };

      sparklesPackages = {
        wasi-wasip1 = wasiPreviews.wasip1;
        wasi-wasip2 = wasiPreviews.wasip2;
        wasi-wasip3-experimental = wasiPreviews.wasip3;
        ldc-sparkles-wasi-runtime-wasip1 = wasiRuntimes.wasip1;
        ldc-sparkles-wasi-runtime-wasip2 = wasiRuntimes.wasip2;
        ldc-sparkles-wasi-runtime-wasip3-experimental = wasiRuntimes.wasip3;
        ldc-sparkles = withWasi [
          "wasip1"
          "wasip2"
        ];
        ldc-sparkles-wasip3-experimental = withWasi [
          "wasip1"
          "wasip2"
          "wasip3"
        ];
      };
    in
    {
      overlayAttrs = self'.packages;
      legacyPackages = {
        # A stdenv whose C and C++ compiler is `clang-sparkles`.
        clangStdenv-sparkles = clangStdenvSparkles;
      }
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
      // optionalAttrs pkgs.stdenv.hostPlatform.isx86 (
        {
          dmd-bootstrap = self'.packages."dmd-binary-2_098_0";
          dmd = self'.packages."dmd-2_112_0";
        }
        // (genPkgVersions "dmd").flattened "binary"
        // (genPkgVersions "dmd").flattened "source"
      )
      // optionalAttrs (ndkHostTag != null) androidPackages
      // optionalAttrs (system == "x86_64-linux") x86_32Packages
      // optionalAttrs (pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin) (
        vulkanPackages // sparklesPackages
      )
      // optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        llvmRuntimePackages // { lld-sparkles = lldSparkles; }
      );

      checks =
        optionalAttrs (pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin) {
          toolchain-clang = vulkanPackages.clang-sparkles.tests.clang;
          toolchain-runtimes = vulkanPackages.ldc-vulkan.tests.runtimes;
          toolchain-ldc = vulkanPackages.ldc-vulkan.tests.ldc;
        }
        // optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          toolchain-llvm-runtimes = pkgs.callPackage ./ldc/llvm-runtimes-tests.nix {
            ldc = llvmRuntimePackages.ldc-vulkan-llvm-runtimes;
          };
        }
        // lib.concatMapAttrs (name: runtime: {
          "wasi-${name}-runtime" = runtime.tests.runners;
          "wasi-${name}-programs" = pkgs.callPackage ./ldc/wasi-tests.nix {
            ldc = sparklesPackages.ldc-sparkles;
            inherit (runtime) target;
          };
        }) (removeAttrs wasiRuntimes [ "wasip3" ]);
    };
}
