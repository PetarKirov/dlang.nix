## Running DMD on macOS aarch64 (Apple Silicon)

### Getting started

1. [Install Nix][install-nix]
2. Use this template in a new folder:

   ```sh
   mkdir test && cd test

   nix flake init -t github:PetarKirov/dlang-nix#macos-aarch64-devshell-for-dmd
   ```

3. Activate the development environment

   * Option A) If you have `direnv` [installed][direnv-hook], simply enable it
     for this dir to activate the Nix development environment in your current
     shell:

     ```sh
     direnv allow
     ```
   * Option B) If not, run this, which will spawn a new shell with the new
     development environment:

     ```
     nix develop .#devShells.x86_64-darwin.default
     ```

---

Now you should have `dmd`, `rdmd`, and `dub` available in your shell:

```sh
dmd -run ./hello.d
Hello, world!

dub --single pegged_example.d
    Starting Performing "debug" build using dmd for x86_64.
  Up-to-date pegged 0.4.9: target for configuration [default] is up to date.
    Building pegged_example ~master: building configuration [application]
["1", "+", "2", "-", "(", "3", "*", "x", "-", "5", ")", "*", "6"]
     Linking pegged_example
    Finished To force a rebuild of up-to-date targets, run again with --force
     Running pegged_example
Arithmetic[0, 17]["1", "+", "2", "-", "(", "3", "*", "x", "-", "5", ")", "*", "6"]
 +-Arithmetic.Term[0, 17]["1", "+", "2", "-", "(", "3", "*", "x", "-", "5", ")", "*", "6"]
    +-Arithmetic.Factor[0, 2]["1"]
    |  +-Arithmetic.Primary[0, 2]["1"]
    |     +-Arithmetic.Number[0, 2]["1"]
    +-Arithmetic.Add[2, 6]["+", "2"]
    |  +-Arithmetic.Factor[4, 6]["2"]
    |     +-Arithmetic.Primary[4, 6]["2"]
    |        +-Arithmetic.Number[4, 6]["2"]
    +-Arithmetic.Sub[6, 17]["-", "(", "3", "*", "x", "-", "5", ")", "*", "6"]
       +-Arithmetic.Factor[8, 17]["(", "3", "*", "x", "-", "5", ")", "*", "6"]
          +-Arithmetic.Primary[8, 15]["(", "3", "*", "x", "-", "5", ")"]
          |  +-Arithmetic.Parens[8, 15]["(", "3", "*", "x", "-", "5", ")"]
          |     +-Arithmetic.Term[9, 14]["3", "*", "x", "-", "5"]
          |        +-Arithmetic.Factor[9, 12]["3", "*", "x"]
          |        |  +-Arithmetic.Primary[9, 10]["3"]
          |        |  |  +-Arithmetic.Number[9, 10]["3"]
          |        |  +-Arithmetic.Mul[10, 12]["*", "x"]
          |        |     +-Arithmetic.Primary[11, 12]["x"]
          |        |        +-Arithmetic.Variable[11, 12]["x"]
          |        +-Arithmetic.Sub[12, 14]["-", "5"]
          |           +-Arithmetic.Factor[13, 14]["5"]
          |              +-Arithmetic.Primary[13, 14]["5"]
          |                 +-Arithmetic.Number[13, 14]["5"]
          +-Arithmetic.Mul[15, 17]["*", "6"]
             +-Arithmetic.Primary[16, 17]["6"]
                +-Arithmetic.Number[16, 17]["6"]
```

You can even run the sample programs directly via the [shebang][shebang] trick:

```sh
chmod +x ./hello.d
./hello.d
Hello, world!

chmod +x ./pegged_example.d
./pegged_example.d
["1", "+", "2", "-", "(", "3", "*", "x", "-", "5", ")", "*", "6"]
Arithmetic[0, 17]["1", "+", "2", "-", "(", "3", "*", "x", "-", "5", ")", "*", "6"]
 +-Arithmetic.Term[0, 17]["1", "+", "2", "-", "(", "3", "*", "x", "-", "5", ")", "*", "6"]
    +-Arithmetic.Factor[0, 2]["1"]
    |  +-Arithmetic.Primary[0, 2]["1"]
    |     +-Arithmetic.Number[0, 2]["1"]
    +-Arithmetic.Add[2, 6]["+", "2"]
    |  +-Arithmetic.Factor[4, 6]["2"]
    |     +-Arithmetic.Primary[4, 6]["2"]
    |        +-Arithmetic.Number[4, 6]["2"]
    +-Arithmetic.Sub[6, 17]["-", "(", "3", "*", "x", "-", "5", ")", "*", "6"]
       +-Arithmetic.Factor[8, 17]["(", "3", "*", "x", "-", "5", ")", "*", "6"]
          +-Arithmetic.Primary[8, 15]["(", "3", "*", "x", "-", "5", ")"]
          |  +-Arithmetic.Parens[8, 15]["(", "3", "*", "x", "-", "5", ")"]
          |     +-Arithmetic.Term[9, 14]["3", "*", "x", "-", "5"]
          |        +-Arithmetic.Factor[9, 12]["3", "*", "x"]
          |        |  +-Arithmetic.Primary[9, 10]["3"]
          |        |  |  +-Arithmetic.Number[9, 10]["3"]
          |        |  +-Arithmetic.Mul[10, 12]["*", "x"]
          |        |     +-Arithmetic.Primary[11, 12]["x"]
          |        |        +-Arithmetic.Variable[11, 12]["x"]
          |        +-Arithmetic.Sub[12, 14]["-", "5"]
          |           +-Arithmetic.Factor[13, 14]["5"]
          |              +-Arithmetic.Primary[13, 14]["5"]
          |                 +-Arithmetic.Number[13, 14]["5"]
          +-Arithmetic.Mul[15, 17]["*", "6"]
             +-Arithmetic.Primary[16, 17]["6"]
                +-Arithmetic.Number[16, 17]["6"]
```

[install-nix]: https://zero-to-nix.com/start/install
[direnv-hook]: https://direnv.net/docs/hook.html
[shebang]: https://en.wikipedia.org/wiki/Shebang_(Unix)
