# Small packages cut from the `llvm-spirv-vulkan` install, which holds LLVM's
# static libraries and every tool, so that nothing needs the install itself
# at run time:
#
# - `dev`: what builds against LLVM read (`llvm-config`, the headers and the
#   static libraries of LLVM and lld), as links into the install, with no
#   compiler or linker driver on its `bin/`: a build that puts it on `PATH`
#   finds the stdenv's wrapped compiler, never a raw one. `llvm-config`
#   resolves its own path, so it still reports the install's directories.
# - `clang`: copies of clang, lld, the shared `libLLVM` and `libclang-cpp`,
#   clang's built-in headers and the LLVM tools that pair with compiler-rt's
#   runtimes (symbolizer, profile and coverage tools, XRay). The compiler
#   ./clang.nix wraps; `disallowedReferences` asserts it names no path of the
#   install.
{
  lib,
  stdenv,
  runCommand,
  darwin,
  # The `llvm-spirv-vulkan` install.
  llvm,
}:
let
  major = lib.versions.major llvm.version;
  inherit (stdenv.hostPlatform) isDarwin;
  sharedLib = stdenv.hostPlatform.extensions.sharedLibrary;
  buildStatus = {
    build = true;
    check = false;
  };

  # Compiler and linker drivers, kept out of `dev`'s `bin/`.
  drivers = [
    "clang"
    "clang++"
    "clang-cpp"
    "clang-${major}"
    "clang-cl"
    "lld"
    "ld.lld"
    "ld64.lld"
    "lld-link"
    "wasm-ld"
  ];

  # The tools `clang` keeps beside the drivers.
  tools = [
    "llvm-ar"
    "llvm-ranlib"
    "llvm-nm"
    "llvm-objcopy"
    "llvm-strip"
    "llvm-objdump"
    "llvm-readobj"
    "llvm-readelf"
    "llvm-size"
    "llvm-strings"
    "llvm-cxxfilt"
    "llvm-symbolizer"
    "llvm-addr2line"
    "llvm-profdata"
    "llvm-cov"
    "llvm-xray"
  ]
  ++ lib.optionals isDarwin [
    "dsymutil"
    "llvm-lipo"
  ];

  # The install's rpaths and install names point at its own `lib/`; point
  # them at the copy.
  relink =
    if isDarwin then
      ''
        for f in $out/bin/* $out/lib/*${sharedLib}*; do
          [ -L "$f" ] && continue
          for dep in $(otool -L "$f" | awk 'NR > 1 { print $1 }' | grep '^${llvm}/'); do
            install_name_tool -change "$dep" "$out/''${dep#${llvm}/}" "$f"
          done
          case "$f" in
            *${sharedLib}*) install_name_tool -id "$out/lib/$(basename "$f")" "$f" ;;
          esac
          for rp in $(otool -l "$f" | awk '/LC_RPATH/ { getline; getline; print $2 }' | grep '^${llvm}/'); do
            install_name_tool -rpath "$rp" "$out/''${rp#${llvm}/}" "$f"
          done
        done
      ''
    else
      ''
        # A variable, so the path's slashes are not read as the delimiter.
        install=${llvm}
        for f in $out/bin/* $out/lib/*${sharedLib}*; do
          [ -L "$f" ] && continue
          rpath=$(patchelf --print-rpath "$f")
          patchelf --set-rpath "''${rpath//$install/$out}" "$f"
        done
      '';
in
{
  dev =
    runCommand "llvm-spirv-vulkan-dev-${llvm.version}"
      {
        passthru.buildStatus = buildStatus;
      }
      ''
        mkdir -p $out/bin
        ln -s ${llvm}/include $out/include
        ln -s ${llvm}/lib $out/lib
        for tool in ${llvm}/bin/*; do
          case " ${lib.concatStringsSep " " drivers} " in
            *" $(basename "$tool") "*) ;;
            *) ln -s "$tool" $out/bin/ ;;
          esac
        done
      '';

  clang = stdenv.mkDerivation {
    pname = "clang-sparkles-unwrapped";
    inherit (llvm) version;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    # Editing a Mach-O voids its ad-hoc signature, and arm64 macOS refuses to
    # run an unsigned binary: the fixup phase signs them again.
    nativeBuildInputs = lib.optional isDarwin darwin.autoSignDarwinBinariesHook;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/lib/clang/${major}
      for tool in ${lib.concatStringsSep " " (drivers ++ tools)}; do
        if [ -L ${llvm}/bin/$tool ]; then
          cp -P ${llvm}/bin/$tool $out/bin/
        elif [ -e ${llvm}/bin/$tool ]; then
          cp ${llvm}/bin/$tool $out/bin/
        fi
      done
      cp -P ${llvm}/lib/libLLVM*${sharedLib}* ${llvm}/lib/libclang-cpp*${sharedLib}* $out/lib/
      cp -r ${llvm}/lib/clang/${major}/include $out/lib/clang/${major}/
      chmod -R u+w $out
      ${relink}
      runHook postInstall
    '';

    disallowedReferences = [ llvm ];

    passthru = {
      inherit buildStatus;
      isClang = true;
      langC = true;
      langCC = true;
    };

    meta = llvm.meta // {
      description = "clang, lld and the shared LLVM libraries of llvm-spirv-vulkan";
    };
  };
}
