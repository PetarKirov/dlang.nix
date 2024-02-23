<div align="center" style="margin: 1em 0 3em 0;">

# ![dlang-nix][dlang-nix-badge]

</div>

<div align="center">

[![Built with Nix][built-with-nix-badge]][nix]
[![Built with D][built-with-d-badge]][d]
![GitHub Actions][github-actions-badge]
![GitHub License][github-license-badge]

</div>

This projects provides Nix derivations for building reproducible and declarative
development environments for the D programming language.

## Support Matrix

| package      | version range                          | platforms                      |
| ------------ | -------------------------------------- | ------------------------------ |
| `dmd-binary` | 2.079.1 - 2.090.1, 2.098.0             | ✅ Linux x86_64, ✅ macOS x86_64 |
| `dmd`        | 2.098.1, 2.100.2, 2.102.2              | ✅ Linux x86_64, ✅ macOS x86_64 |
| `ldc-binary` | 1.19.0, 1.25.0, 1.28.0, 1.32.1, 1.34.0 | ✅ Linux x86_64, ✅ macOS x86_64 |
| `ldc`        | 1.30.0                                 | ✅ Linux x86_64, ❌ macOS x86_64 |
| `dub`        | 1.30.0                                 | ✅ Linux x86_64, ✅ macOS x86_64 |

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
➤ nix profile install d#dmd d#dub d#ldc
```

#### Build multiple versions of DMD and DUB in parallel

```bash
➤ nix build -L --json \
  github:PetarKirov/dlang-nix#dmd-2_098_1 \
  github:PetarKirov/dlang-nix#dmd-2_100_2 \
  github:PetarKirov/dlang-nix#dmd-2_102_2 \
  github:PetarKirov/dlang-nix#dub-1_30_0
```

Or if you're inside this repo:

```bash
➤ nix build -L --json \
  .#dmd-2_098_1 \
  .#dmd-2_100_2 \
  .#dmd-2_102_2 \
  .#dub-1_30_0
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
      perSystem = { inputs', pkgs, ... }: {
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

You can find the full example in [`templates/devshell/`](./templates/devshell/).

### Pre-flakes usage

The `default.nix` file in the root of this repo is a
[shim](https://nixos.wiki/wiki/Flakes#Using_flakes_with_stable_Nix) that
exposes all flake outputs as Nix attributes. This is useful for users who
haven't yet made the jump to the Nix Flakes world.

For example, if you have an existing `shell.nix` file, all you need to do is add
the changes marked as "NEW" from the snippet below:

```nix
{pkgs ? import <nixpkgs> {}}: let
  # NEW: Import the dlang-nix Nix library:
  dlang-nix = import (pkgs.fetchFromGitHub {
    owner = "PetarKirov";
    repo = "dlang.nix";
    rev = "b9b7ef694329835bec97aa78e93757c3fbde8e13";
    hash = "sha256-zNvuU0DFSfCtQPFQ3rxri2e3mlMzLtJB/qaDsS0i9Gg=";
  });

  # NEW: Add `dpkgs` shorthand:
  dpkgs = dlang-nix.packages."${pkgs.system}";
in
  pkgs.mkShell {
    packages = [
      # NEW: Reference D-related packages from `dpkgs`:
      dpkgs.dmd
      dpkgs.dub
    ];
  }
```

You can find the full example in
[`templates/pre-flake-devshell/`](./templates/pre-flake-devshell/).

It should be noted that unlike most traditional Nix projects, this will not
build the compilers using your `<nixpkgs>`. Instead it will build them using a
fixed Nixpkgs version defined in `flake.lock` of this project. Indeed this is
one of the differences how things are usually done with and without flakes,
even when it's possible to either pin or to not pin the nixpkgs version
regardless of flake use.

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
