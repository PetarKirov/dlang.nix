# Windows (MSVC) runtime import libraries from the official LDC release
# archive — druntime-ldc.lib, phobos2-ldc.lib, ldc_rt.* and friends — for
# *cross-linking* D programs that target x86_64-pc-windows-msvc from a
# non-Windows host:
#
#     ldc2 -mtriple=x86_64-pc-windows-msvc -link-internally -mscrtlib=msvcrt \
#         app.d "-L/LIBPATH:${ldc-binary-windows-libs}" \
#         "-L/LIBPATH:<MSVC CRT + Windows SDK import libs>"
#
# The host compiler must be an `ldc-binary-*` package of the *same version*
# (the official binaries ship with integrated LLD, so `-link-internally`
# works; source-built LDC may not). The MSVC CRT / Windows SDK import libs
# are out of scope here — nixpkgs' `windows.sdk` (xwin) provides them.
#
# This intentionally reuses the `windows-x64` entry that already exists for
# every version in supported-binary-versions.json; it is not a host package
# (no executables are usable on the build platform), just a lib directory.
{
  lib,
  stdenvNoCC,
  fetchurl,
  p7zip,
  version ? "1.42.0",
  arch ? "x64", # "x64" or "x86"
}:
let
  hashes =
    (builtins.fromJSON (builtins.readFile ./supported-binary-versions.json)).${version}
      or (throw "ldc-binary-windows-libs: unknown LDC version ${version}");
  archivePlatform = "windows-${arch}";
  hash =
    hashes.${archivePlatform}
      or (throw "ldc-binary-windows-libs: no ${archivePlatform} archive hash for LDC ${version}");
  archiveName = "ldc2-${version}-${archivePlatform}";
in
stdenvNoCC.mkDerivation {
  pname = "ldc-binary-windows-${arch}-libs";
  inherit version;

  src = fetchurl {
    name = "${archiveName}.7z";
    url = "https://github.com/ldc-developers/ldc/releases/download/v${version}/${archiveName}.7z";
    sha256 = hash;
  };

  nativeBuildInputs = [ p7zip ];

  unpackPhase = ''
    runHook preUnpack
    7z x $src "${archiveName}/lib/*"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r ${archiveName}/lib/. $out/
    runHook postInstall
  '';

  meta = {
    description = "LDC druntime/phobos MSVC import libraries (${archivePlatform}) for cross-linking";
    homepage = "https://github.com/ldc-developers/ldc";
    license = lib.licenses.bsd3;
    # The libs target Windows, but the package is *used* on the cross host.
    platforms = lib.platforms.all;
  };
}
