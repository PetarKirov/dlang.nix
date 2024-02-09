{
  version,
  hashes,
}: {
  lib,
  stdenv,
  fetchurl,
  curl,
  tzdata,
  autoPatchelfHook,
  fixDarwinDylibNames,
  libxml2,
  ...
}: let
  inherit (stdenv) hostPlatform system;

  inherit (import ../../lib/build-status.nix {inherit lib;}) getBuildStatus;
  buildStatus = getBuildStatus "ldc" version stdenv.system;

  systemToArchivePlatform = {
    # FIXME: How should Android be supported?
    # (It is not a separate Nixpkgs platform.)
    "aarch64-android" = "android-aarch64";
    "armv7a-android" = "android-armv7a";
    "x86_64-freebsd" = "freebsd-x86_64";
    "aarch64-linux" = "linux-aarch64";
    "x86_64-linux" = "linux-x86_64";
    "aarch64-darwin" = "osx-arm64";
    "x86_64-darwin" = "osx-x86_64";
    "x86_64-windows" = "windows-x64";
    "i686-windows" = "windows-x86";
  };

  defaultSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

  supportedSystems = lib.pipe (builtins.attrNames systemToArchivePlatform) [
    (builtins.filter (x: builtins.elem x defaultSystems))
    (builtins.filter (sys: hashes.${systemToArchivePlatform.${sys}} != null))
  ];

  tarballSuffix =
    if hostPlatform.isWindows
    then "7z"
    else "tar.xz";

  archivePlatform = systemToArchivePlatform."${system}";
in
  stdenv.mkDerivation {
    pname = "ldc-binary";
    inherit version;

    passthru = {
      inherit buildStatus supportedSystems hashes;
    };

    src = fetchurl rec {
      name = "ldc2-${version}-${archivePlatform}.${tarballSuffix}";
      url = "https://github.com/ldc-developers/ldc/releases/download/v${version}/${name}";
      sha256 = hashes."${archivePlatform}" or (throw "missing bootstrap sha256 for ${archivePlatform}");
    };

    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs =
      lib.optional hostPlatform.isLinux autoPatchelfHook
      ++ lib.optional hostPlatform.isDarwin fixDarwinDylibNames;

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [libxml2 stdenv.cc.cc];

    propagatedBuildInputs = [curl tzdata];

    installPhase = ''
      mkdir -p $out

      mv bin etc import lib LICENSE README $out/
    '';

    meta = with lib; {
      description = "The LLVM-based D Compiler";
      homepage = "https://github.com/ldc-developers/ldc";
      # from https://github.com/ldc-developers/ldc/blob/master/LICENSE
      license = with licenses; [bsd3 boost mit ncsa gpl2Plus];
      maintainers = with maintainers; [ThomasMader lionello];
      platforms = supportedSystems;
    };
  }
