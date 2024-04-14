{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "juliad";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "symmetryinvestments";
    repo = "juliad";
    rev = "v${version}";
    hash = "sha256-uZa4g5tJ0SYbmOHe1uAiy6I9K5iBoM7+bheWD8XmFWQ=";
  };

  dontdubTest = true;

  meta = with lib; {
    description = "Embed Julia in Dlang";
    homepage = "https://github.com/symmetryinvestments/juliad";
    # license = licenses.unfree; # FIXME: nix-init did not found a license
    maintainers = with maintainers; [];
    mainProgram = "juliad";
    platforms = platforms.all;
  };
}
