{lib}: rec {
  # Mapping from $DC to $DMD name
  dcToDmdMapping = {
    "dmd" = "dmd";
    "ldc" = "ldmd2";
    "gdc" = "gdmd";
  };

  getDmdWrapper = dCompilerPackage: let
    name = lib.strings.removeSuffix "-binary" dCompilerPackage.pname;
    xDmdWrapperName = dcToDmdMapping."${name}";
  in "${dCompilerPackage}/bin/${xDmdWrapperName}";
}
