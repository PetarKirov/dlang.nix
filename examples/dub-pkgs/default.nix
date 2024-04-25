{
  buildDubPackage,
  self',
  pkgs,
}: rec {
  tsv-utils = pkgs.callPackage ./tsv-utils {
    dub = self'.packages.dub;
    dmd = self'.packages.dmd;
  };
  inochi2d = pkgs.callPackage ./inochi2d {
    inherit buildDubPackage;
  };
  graphqld = pkgs.callPackage ./graphqld {
    inherit buildDubPackage;
  };
  dubproxy = pkgs.callPackage ./dubproxy {
    inherit buildDubPackage;
  };
  faked = pkgs.callPackage ./faked {
    inherit buildDubPackage;
  };
  juliad = pkgs.callPackage ./juliad {
    inherit buildDubPackage;
  };
  libbetterc = pkgs.callPackage ./libbetterc {
    inherit buildDubPackage;
  };
  symmetry-gelf = pkgs.callPackage ./symmetry-gelf {
    inherit buildDubPackage;
  };
  xlsxreader = pkgs.callPackage ./xlsxreader {
    inherit buildDubPackage;
  };
  mir-algorithm = pkgs.callPackage ./mir-algorithm {
    inherit buildDubPackage;
  };
  mir-optim = pkgs.callPackage ./mir-optim {
    inherit buildDubPackage;
  };
  dpp = pkgs.callPackage ./dpp {
    inherit buildDubPackage;
  };
  lubeck = pkgs.callPackage ./lubeck {
    inherit buildDubPackage;
  };
  dust-mite = pkgs.callPackage ./dust-mite {
    inherit buildDubPackage;
  };
  concurrency = pkgs.callPackage ./concurrency {
    inherit buildDubPackage;
  };
  arsd = pkgs.callPackage ./arsd {
    inherit buildDubPackage;
  };
}
