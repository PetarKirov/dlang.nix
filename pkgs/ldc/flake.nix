{
  inputs = {
    ldc = {
      url = "github:ldc-developers/ldc";
      flake = false;
    };
    primary.follows = "ldc";
  };
}
