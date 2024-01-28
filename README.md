<div align="center" style="margin: 1em 0 3em 0;">

# ![dlang-nix][dlang-nix-badge]

</div>

<div align="center">

[![Built with Nix][built-with-nix-badge]][nix]
[![Built with D][built-with-d-badge]][d]
![GitHub Actions][github-actions-badge]
![GitHub License][github-license-badge]

</div>

This projects provides Nix derivations for building reproducible and declarative development environments for the D programming language.

Currently

This project provides Nix expressions for building DMD, LDC and DUB.

## Usage

### Nix Flakes

While Nix Flakes are still experimental, they are the recommended way to use
this project, as `flake.lock` files ensure that you will be able to reproduce
the exact same build in the future. Furthermore, Flakes allow you to benefit
from the our binary cache -
[dlang-community.cachix.org][dlang-community-cachix], which is hosted by Cachix.

#### View available packages

```bash
nix flake show github:PetarKirov/dlang-nix
```

#### Enter a shell with a particular version of DMD and DUB installed

```bash
➤ nix shell \
  github:PetarKirov/dlang-nix#dmd-2_102_2 \
  github:PetarKirov/dlang-nix#dub-1_30_0

➤ dmd --version
DMD64 D Compiler v2.102.2

Copyright (C) 1999-2023 by The D Language Foundation, All Rights Reserved written by Walter Bright

➤ dub --version
DUB version 1.30.0, built on Jan  1 1980
```

#### Add to your local Nix flakes registry

```bash
➤ nix registry add d github:PetarKirov/dlang-nix

➤ nix shell d#dmd-2_102_2 d#dub-1_30_0

➤ dmd --version
DMD64 D Compiler v2.102.2

Copyright (C) 1999-2023 by The D Language Foundation, All Rights Reserved written by Walter Bright

➤ dub --version
DUB version 1.30.0, built on Jan  1 1980
```

#### Install packages to your Nix profile

```bash
➤ nix profile install d#dmd-2_102_2 d#dub-1_30_0 d#ldc_
```

#### Creating declarative & reproducible development environment

Add the following `flake.nix` to your project:

```nix
{
  inputs = {
    dlang-nix.url = "github:PetarKirov/dlang-nix";
    nixpkgs.follows = "dlang-nix/nixpkgs";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-darwin"];
      perSystem = { inputs', ... }: {
        devShells.default = pkgs.mkShell {
          packages = [
            inputs'.dlang-nix.packages.ldc
            inputs'.dlang-nix.packages.dub
          ];
        };
      };
    };
}
```

And then run `nix develop` to enter a shell with the latest LDC and DUB installed:

```bash
$ dub
bash: dub: command not found

$ nix develop

$ dub --version
DUB version 1.30.0, built on Jan  1 1980
```

See complete example in [`templates/devshell/flake.nix`](./templates/devshell/flake.nix).

## Source and binary variants

DMD and LDC packages come in two variants: `binary` and `source`.

The `binary` variants are based on the the official DMD and LDC releases, but
repackaged with `autoPatchelfHook` / `fixDarwinDylibNames`.

The `source` variants are built from source using the `binary` package for the
first step of the bootstrap process.

As far as users of this repo are concerned, both the `binary` and `source`
variants are distributed as pre-built binaries via the
[dlang-community.cachix.org][dlang-community-cachix] binary cache.

This is useful for building custom versions of DMD and LDC, or for building DMD
and LDC with custom patches.

[d]: https://dlang.org
[nix]: https://nixos.org

[built-with-nix-badge]: https://img.shields.io/static/v1?logo=nixos&logoColor=white&label=&message=Built%20with%20Nix&color=41439a&style=for-the-badge
[built-with-d-badge]: https://img.shields.io/static/v1?logo=d&logoColor=white&label=&message=Built%20with%20D&color=B03931&style=for-the-badge

[dlang-community-cachix]: https://dlang-community.cachix.org

[github-license-badge]: https://img.shields.io/github/license/PetarKirov/dlang-nix?style=for-the-badge

[github-actions-badge]: https://img.shields.io/badge/github%20actions-black.svg?style=for-the-badge&logo=github&logoColor=white

[dlang-nix-badge]: ./docs/img/dlang.nix-badge.svg
