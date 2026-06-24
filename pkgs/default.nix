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

      # Android NDK cross-compilation toolchain. Opt-in and Linux/x86_64-only
      # (that is the only host the NDK ships prebuilt for here), and it pulls in
      # the *unfree* Android SDK NDK, so it is kept out of the default package
      # set and only materialises when `ldc-android` is built explicitly.
      androidPkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
      ndkBundle = (androidPkgs.androidenv.composeAndroidPackages { includeNDK = true; }).ndk-bundle;
      ndkRoot = "${ndkBundle}/libexec/android-sdk/ndk/${ndkBundle.version}";
      ldcAndroidRuntime = pkgs.callPackage ./ldc/android-runtime.nix {
        ldc = self'.packages.ldc;
        ndk = ndkRoot;
      };
      androidPackages = {
        ldc-android-runtime = ldcAndroidRuntime;
        ldc-android = pkgs.callPackage ./ldc/android.nix {
          ldc = self'.packages.ldc;
          androidRuntime = ldcAndroidRuntime;
          ndk = ndkRoot;
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

      # ---- WebAssembly (wasm32-wasip2) toolchain — x86_64-linux only ----
      # The fork needs LLVM 22 (it references llvm::Triple::WASIp1/2/3), which
      # dlang.nix's nixpkgs lacks. Source the whole wasm env from a pinned nixpkgs
      # that has it, matching the LDC WASI dev shell. Heavy/opt-in, so kept out of
      # the default set like the android packages.
      wasmPkgs = import inputs.nixpkgs-wasm { inherit system; };

      # Merged wasilibc tree (libs + headers).
      wasiSysroot = wasmPkgs.symlinkJoin {
        name = "wasi-sysroot";
        paths = [
          wasmPkgs.pkgsCross.wasi32.wasilibc
          wasmPkgs.pkgsCross.wasi32.wasilibc.dev
        ];
      };

      # WASI component linker.
      wasmComponentLd = wasmPkgs.rustPlatform.buildRustPackage {
        pname = "wasm-component-ld";
        version = "0.5.22";
        src = inputs.wasm-component-ld;
        cargoLock.lockFile = "${inputs.wasm-component-ld}/Cargo.lock";
        doCheck = false;
      };

      compilerRtWasm32 = "${wasmPkgs.pkgsCross.wasi32.llvmPackages_22.compiler-rt}/lib/wasi/libclang_rt.builtins-wasm32.a";
      clangUnwrapped = "${wasmPkgs.llvmPackages_22.clang-unwrapped}/bin/clang";

      # The fork tree (ldc + phobos submodule repointed at PetarKirov/phobos, whose
      # WASI commit is not on upstream), resolved whole via fetchSubmodules.
      ldcWasmForkSrc = wasmPkgs.fetchFromGitHub {
        owner = "PetarKirov";
        repo = "ldc";
        rev = "f4d2f831c30f63c038999d0818d141539d1246c3";
        hash = "sha256-NnVWYWff43epvUY3BlTUF0JAQenqs/4mnZ1ZlDHHPE4=";
        fetchSubmodules = true;
      };

      ldcWasmCompiler =
        wasmPkgs.callPackage
          (import ./ldc/generic.nix {
            version = "1.42.0";
            srcOverride = ldcWasmForkSrc;
            checkOverride = false;
            llvmPackagesOverride = wasmPkgs.llvmPackages_22;
          })
          {
            hostDCompiler = wasmPkgs.ldc;
            inherit (wasmPkgs.darwin.apple_sdk.frameworks) Foundation;
          };

      ldcWasmRuntime = wasmPkgs.callPackage ./ldc/wasm-runtime.nix {
        ldc = ldcWasmCompiler;
        inherit wasiSysroot clangUnwrapped;
      };

      ldcWasm = wasmPkgs.callPackage ./ldc/wasm.nix {
        ldc = ldcWasmCompiler;
        wasmRuntime = ldcWasmRuntime;
        lld = wasmPkgs.llvmPackages_22.lld;
        inherit wasmComponentLd wasiSysroot compilerRtWasm32;
      };

      wasmPackages = {
        ldc-wasm-compiler = ldcWasmCompiler;
        ldc-wasm-runtime = ldcWasmRuntime;
        ldc-wasm = ldcWasm;
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
      // optionalAttrs (system == "x86_64-linux") (androidPackages // wasmPackages // x86_32Packages);
    };
}
