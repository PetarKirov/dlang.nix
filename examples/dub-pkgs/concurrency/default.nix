{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "concurrency";
  version = "5.0.5";

  src = fetchFromGitHub {
    owner = "symmetryinvestments";
    repo = "concurrency";
    rev = "v${version}";
    hash = "sha256-NwKXVzS2SMahamJi1NF+Ltp3LrVZWW+6gHIfnLGxpyk=";
  };

  meta = with lib; {
    description = "Concurrency primitives";
    homepage = "https://github.com/symmetryinvestments/concurrency";
    license = licenses.mit;
    maintainers = with maintainers; [];
    mainProgram = "concurrency";
    platforms = platforms.all;
  };
}
