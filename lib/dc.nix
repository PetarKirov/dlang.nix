{ lib }:
let
  inherit (import ./version-utils.nix { }) versionBetween;
in
rec {
  /**
    Mapping from $DC to $DMD name

    # Type

    ```
    dcToDmdMapping :: AttrSet String
    ```
  */
  dcToDmdMapping = {
    "dmd" = "dmd";
    "ldc" = "ldmd2";
    "gdc" = "gdmd";
  };

  /**
    Removes the "-binary" suffix (if any) from the package name.

    # Type

    ```
    normalizedName :: String -> String
    ```

    # Examples:

    ```nix
    normalizedName "dmd"
    => "dmd"

    normalizedName "dmd-binary"
    => "dmd"

    normalizedName "ldc-binary"
    => "ldc"
    ```
  */
  normalizedName = name: lib.strings.removeSuffix "-binary" name;

  /**
    Given an LDC version, returns the approximate DMD frontend version.

    # Type

    ```
    ldcToDmdVersion :: String -> String
    ```

    # Examples:

    ```nix
    ldcToDmdVersion "1.23.0"
    => "2.093.1"

    ldcToDmdVersion "1.1.0"
    => "2.071.1"

    ldcToDmdVersion "1.38.0"
    => "2.108.1"
    ```
  */
  ldcToDmdVersion =
    ldcVersion:
    let
      minor = 70 + (lib.toInt (lib.versions.minor ldcVersion));
      mid = if minor < 100 then "0" + toString minor else toString minor;
    in
    "2.${mid}.1";

  /**
    Given a D compiler derivation, returns the information needed to
    generate a DMD frontend wrapper.

    # Type

    ```
    getDCInfo :: Derivation -> { name, dmdWrapperName, dmdWrapper, frontendVersion }
    ```

    # Examples:

    ```nix
    getDCInfo {
      pname = "dmd";
      version = "2.093.1";
      # ...
    }
    => {
      name = "dmd";
      dmdWrapperName = "dmd";
      dmdWrapper = "/nix/store/...-dmd/bin/dmd";
      frontendVersion = "2.093.1";
    }

    getDCInfo {
      pname = "ldc";
      version = "1.23.0";
      # ...
    }
    => {
      name = "ldc";
      dmdWrapperName = "ldmd2";
      dmdWrapper = "/nix/store/...-ldc/bin/ldmd2";
      frontendVersion = "2.093.1";
    }
    ```
  */
  getDCInfo =
    dCompilerDrv@{ pname, version, ... }:
    let
      name = normalizedName pname;
      dmdWrapperName = dcToDmdMapping."${name}";
      dmdWrapper = "${dCompilerDrv}/bin/${dmdWrapperName}";
      frontendVersion =
        if name == "dmd" then
          version
        else if name == "ldc" then
          ldcToDmdVersion version
        else
          throw "Unsupported compiler '${name}'";
    in
    {
      inherit
        name
        dmdWrapperName
        dmdWrapper
        frontendVersion
        ;

      frontendVersionBetween =
        minVersion: maxVersion: versionBetween minVersion maxVersion frontendVersion;
    };
}
