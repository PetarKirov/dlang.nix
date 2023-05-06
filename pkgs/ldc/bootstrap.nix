{callPackage}:
callPackage ./binary.nix {
  version = "1.32.1";
  hashes = {
    # COMPILER=ldc VERSION=1.32.1 ./scripts/fetch-binary
    "android-aarch64" = "sha256-VT64VTqr4IfVXThw1Ycf0Wrx3ICJkm4ofuGG+gCJfDQ=";
    "android-armv7a" = "sha256-wdEuHjD9NwtQ0goeiB1ExrzFE2X4Vnk1GhVZrleL4vU=";
    # "freebsd-x86_64" = "<not available>";
    "linux-aarch64" = "sha256-VZJFDzsiEuf/L8VbFWd+KtEyrkHp0mX2i9TuKC6zcTM=";
    "linux-x86_64" = "sha256-IRW4A689ysDCXbHJvFuQRMgkW1CI7UPzKChe1uLrkgk=";
    "osx-arm64" = "sha256-b1+9tgFmaeEdE82PqXAwpLIxarrpgMP9pq+5IvdyUVM=";
    "osx-x86_64" = "sha256-uoQi4QqHFB/o7QSVCZZVnkacTn4VIP6ywc30ikRRX6A=";
    "windows-x64" = "sha256-toR9xnw5B4H8/8tG2zo3mp93cdQHnY0cS3AujGenUBo=";
    "windows-x86" = "sha256-ffQnS+HbtN6STK+wQ7jfS77m8BO+DwsevOAnhKy0jz4=";
  };
}
