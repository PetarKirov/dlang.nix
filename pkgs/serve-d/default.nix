{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "serve-d";
  version = "0.7.6";

  src = fetchFromGitHub {
    owner = "Pure-D";
    repo = "serve-d";
    rev = "v${version}";
    hash = "sha256-h4zsW8phGcI4z0uMCIovM9cJ6hKdk8rLb/Jp4X4dkpk=";
  };

  meta = with lib; {
    description = "D LSP server (dlang language server protocol server";
    homepage = "https://github.com/Pure-D/serve-d";
    license = licenses.mit;
    maintainers = with maintainers; [];
    mainProgram = "serve-d";
    platforms = platforms.all;
  };
}
