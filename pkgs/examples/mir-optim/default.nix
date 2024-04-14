{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "mir-optim";
  version = "1.4.5";

  src = fetchFromGitHub {
    owner = "libmir";
    repo = "mir-optim";
    rev = "v${version}";
    hash = "sha256-i829jl+7vctYEO5gVjNUPR7xGgNhR8aT+JNHhjAzgXc=";
  };

  dubSelections = ./dub.selections.json;

  dontDubTest = true;

  meta = with lib; {
    description = "BetterC Nonlinear Optimization Framework";
    homepage = "https://github.com/libmir/mir-optim";
    # license = licenses.unfree; # FIXME: nix-init did not found a license
    maintainers = with maintainers; [];
    mainProgram = "mir-optim";
    platforms = platforms.all;
  };
}
