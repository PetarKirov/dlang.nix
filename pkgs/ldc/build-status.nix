{ lib }:
{
  "1.30.0" = {
    aarch64-darwin = {
      build = false;
      check = false;
      skippedTests = [ ];
    };
    x86_64-darwin = {
      build = false;
      check = false;
      skippedTests = [ ];
    };
    x86_64-linux = {
      build = true;
      check = false;
      skippedTests = [ ];
    };
  };
  "1.42.0" = {
    aarch64-darwin = {
      build = true;
      check = false;
      skippedTests = [ ];
    };
    x86_64-darwin = {
      build = true;
      check = false;
      skippedTests = [ ];
    };
    aarch64-linux = {
      build = true;
      check = false;
      skippedTests = [ ];
    };
    x86_64-linux = {
      build = true;
      check = false;
      skippedTests = [ ];
    };
  };
}
