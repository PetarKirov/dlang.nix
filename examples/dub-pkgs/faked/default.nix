{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "faked";
  version = "6.0.1";

  src = fetchFromGitHub {
    owner = "symmetryinvestments";
    repo = "faked";
    rev = "v${version}";
    hash = "sha256-wFenQqhqcoWYEmlvdXRUMUGBuQ4tdYLHaDVuyBtT+8g=";
  };

  meta = with lib; {
    description = "D library to create real fake data";
    homepage = "https://github.com/symmetryinvestments/faked";
    license = licenses.mit;
    maintainers = with maintainers; [];
    mainProgram = "faked";
    platforms = platforms.all;
  };
}
