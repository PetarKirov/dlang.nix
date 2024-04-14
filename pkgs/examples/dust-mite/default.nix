{
  lib,
  buildDubPackage,
  fetchFromGitHub,
}:
buildDubPackage rec {
  pname = "dust-mite";
  version = "0.0.430";

  src = fetchFromGitHub {
    owner = "CyberShadow";
    repo = "DustMite";
    rev = "v${version}";
    hash = "sha256-gtNzxv2UeLfA2sPV/MqSl1Xuw98AftfttyAXBCnnDgk=";
  };

  meta = with lib; {
    description = "General-purpose data reduction tool";
    homepage = "https://github.com/CyberShadow/DustMite";
    license = licenses.boost;
    maintainers = with maintainers; [];
    mainProgram = "dust-mite";
    platforms = platforms.all;
  };
}
