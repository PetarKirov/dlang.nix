import ./binary.nix {
  version = "2.098.0";
  hashes = {
    # COMPILER=dmd VERSION=2.098.0 ./scripts/fetch-binary
    "linux" = "sha256-EQTl5Z/UeCi3mNd6cr5Ue/CGu6HTdKGFXGtYFMTbAUU=";
    "osx" = "sha256-d4Cq1EKdSZpkfn6Qdwb3dWVr539EJci0rqt5gCTH80I=";
    "freebsd-64" = "sha256-c7ODMpI/kGdl3R4a7/gSTDzTcD3hbHtl4teHJvT0IGk=";
    "windows" = "sha256-Yhw3hkkVdvHTayxdk/XNKZwrV8cDMfz63rgBqark+gU=";
  };
}
