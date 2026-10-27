# The C side of LDC's WASI target: wasi-sdk's prebuilt sysroot (wasi-libc,
# libc++) and compiler-rt builtins, behind a cross C compiler driver named as
# LDC looks for it — `wasm32-wasip1-clang` (driver/tool.cpp). LDC links WASI
# executables through that driver, which picks the crt and libc, and the
# runtime's C sources are compiled with it.
#
# The release's sysroot and builtins are target code, so the same tarballs
# serve every build host; only the previews in `previews` are kept. The
# driver is the clang of the LLVM that LDC is built against, linking with its
# `wasm-ld`, linked in from the `clang` view of ../llvm-spirv/views.nix, so a
# consumer's closure does not keep the whole LLVM install (static libraries
# and all).
#
# Upstream LDC's CI uses this wasi-sdk release. Older wasi-libc cannot lock a
# recursive mutex twice (WebAssembly/wasi-libc#777), which every druntime
# `Mutex` does.
{
  lib,
  stdenvNoCC,
  fetchurl,
  runtimeShell,
  # The `clang` view of the LLVM LDC is built against (clang, lld).
  clang,
  # The install itself, which nothing here may reference.
  llvm,
  version ? "34",
  # The WASI targets to keep, as wasi-sdk names their directories.
  previews ? [ "wasip1" ],
}:
let
  sysroot = fetchurl {
    url = "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${version}/wasi-sysroot-${version}.0.tar.gz";
    hash = "sha256-nYE1RO7r44t7jyJE7Vkd5GttuBLG3Rolf/nw0qkFor4=";
  };
  builtins = fetchurl {
    url = "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${version}/libclang_rt-${version}.0.tar.gz";
    hash = "sha256-7uPmNNz3GqIrEzM5FiPPXJllpjfcQoonsahYwCbFh/E=";
  };
  clangMajor = lib.versions.major clang.version;
  keep = lib.concatMapStringsSep " " (p: "wasm32-${p}") previews;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "wasi-sdk";
  version = "${version}.0";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    sysroot=$out/share/wasi-sysroot
    mkdir -p $sysroot $out/lib/clang/lib $out/libexec $out/bin

    tar -xzf ${sysroot} -C $sysroot --strip-components=1
    for dir in $sysroot/include/* $sysroot/lib/*; do
      case " ${keep} " in *" $(basename $dir) "*) ;; *) rm -r $dir ;; esac
    done
    rm -rf $sysroot/experimental-*

    tar -xzf ${builtins} -C $out/lib/clang/lib --strip-components=1
    for dir in $out/lib/clang/lib/*; do
      case " ${lib.concatMapStringsSep " " (p: "wasm32-unknown-${p}") previews} " in
        *" $(basename $dir) "*) ;;
        *) rm -r $dir ;;
      esac
    done
    ln -s ${clang}/lib/clang/${clangMajor}/include $out/lib/clang/include

    ln -s ${clang}/bin/clang-${clangMajor} $out/libexec/clang
    ln -s clang $out/libexec/clang++
    ln -s ${clang}/bin/lld $out/libexec/lld
    ln -s lld $out/libexec/wasm-ld

    for exe in clang clang++; do
      cat > $out/bin/wasm32-wasip1-$exe <<DRIVER
    #!${runtimeShell}
    exec $out/libexec/$exe --target=wasm32-wasip1 \\
      --sysroot=$sysroot -resource-dir=$out/lib/clang -B$out/libexec "\$@"
    DRIVER
      chmod +x $out/bin/wasm32-wasip1-$exe
    done

    runHook postInstall
  '';

  disallowedReferences = [ llvm ];

  passthru = {
    buildStatus = {
      build = true;
      check = false;
    };
    cc = "${finalAttrs.finalPackage}/bin/wasm32-wasip1-clang";
    cxx = "${finalAttrs.finalPackage}/bin/wasm32-wasip1-clang++";
  };

  meta = {
    description = "wasi-sdk's WASI sysroot and builtins behind a wasm32-wasip1 clang driver";
    homepage = "https://github.com/WebAssembly/wasi-sdk";
    license = with lib.licenses; [
      asl20
      mit
      ncsa
    ];
    platforms = lib.platforms.unix;
  };
})
