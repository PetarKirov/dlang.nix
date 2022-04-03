{
  inputs = {
    dub = {
      url = "github:dlang/dub";
      flake = false;
    };
    primary.follows = "dub";
  };
}
