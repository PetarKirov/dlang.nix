{callPackage}:
callPackage ./binary.nix {
  version = "1.34.0";
  hashes = {
    # ./scripts/fetch_binary.d --compiler=ldc --version=1.34.0 --dry-run=false
    "android-aarch64" = "sha256-SJRdpd5tzhLPhJuY6rhN7r0Z2gCvEVDZxDMj0+tufUc=";
    "android-armv7a" = "sha256-1URd7kpVA5m8DOPLO+6M3xhKvztHwIvNj2oka8TFcYw=";
    "freebsd-x86_64" = "sha256-vI/ubxF0wyw/KdyoVzv7g4/6JiyJOdwgb/N7T6rne14=";
    "linux-aarch64" = "sha256-LRD817uG0XMf6i+GaqCi/vDuURU4WInhFCeU+dAtHaE=";
    "linux-x86_64" = "sha256-cnmsxGlsElSE2iVQcs+KVHKsKMv6XYin4N+XhUFt/BU=";
    "osx-arm64" = "sha256-W45AEOW1EPsxizCgJYUOZyq7MhotN62xobsEAbr2/tU=";
    "osx-x86_64" = "sha256-93aJN7ZNOLrQmKd6z/435trWg5F6B3XfOmKU/j5M5ig=";
    "windows-x64" = "sha256-WrZnrDo/8hnsOsY2Ih8txErDz3OaNhVzwFFXsPJCEFM=";
    "windows-x86" = "sha256-Vu/W9z7cB7VrcBqrlClknCYYni+GCDB4baGZOT6JS54=";
  };
}
