# D programs compiled for one WASI preview by an LDC from ./with-wasi.nix and
# run under wasmtime: module constructors, the GC, and exceptions; then the
# same C library call with and without link-time optimization, where the LTO
# build must have inlined it from the sysroot's LTO libc (Sparkles' toolchain
# specification, TCW3), and no legacy exception-handling instruction may
# survive the link.
{
  runCommand,
  wasmtime,
  wasm-tools,
  writeText,
  ldc,
  target,
}:
let
  runtime = writeText "runtime.d" ''
    module runtime;

    import std.array, std.conv, std.stdio;

    int initialized;
    static this() { initialized = 42; }

    class Boom : Exception { this(string m) { super(m); } }
    void thrower(int n) { if (n > 2) throw new Boom("boom " ~ n.to!string); }

    void main()
    {
        int[] xs;
        foreach (i; 0 .. 100_000) xs ~= i;
        string caught;
        try thrower(3); catch (Boom e) caught = e.msg;
        writefln("ctor %s, gc %s, caught %s", initialized, xs.length, caught);
    }
  '';
  inlining = writeText "inlining.d" ''
    module inlining;

    import core.stdc.stdio : printf;
    import core.stdc.stdlib : div;

    void main(string[] args)
    {
        auto q = div(cast(int) args.length + 83, 2);
        printf("%d\n", q.quot);
    }
  '';
in
runCommand "ldc-wasi-tests-${target}"
  {
    nativeBuildInputs = [
      ldc
      wasmtime
      wasm-tools
    ];
  }
  ''
    export HOME=$TMPDIR
    run() { wasmtime run -W exceptions=y "$@"; }
    expect() {
      if [ "$1" != "$2" ]; then
        echo "expected '$2', got '$1'"
        exit 1
      fi
    }

    ldc2 -mtriple=${target} ${runtime} -of=runtime.wasm
    expect "$(run runtime.wasm)" "ctor 42, gc 100000, caught boom 3"

    ldc2 -mtriple=${target} -O ${inlining} -of=plain.wasm
    ldc2 -mtriple=${target} -O -flto=full \
      -defaultlib=phobos2-ldc-lto,druntime-ldc-lto ${inlining} -of=lto.wasm
    for m in plain lto; do
      expect "$(run $m.wasm)" 42
      wasm-tools print $m.wasm > $m.wat
    done
    grep -qE 'call [$]div( |$)' plain.wat || { echo "plain.wasm does not call div"; exit 1; }
    if grep -qE 'call [$]div( |$)' lto.wat; then
      echo "div was not inlined under LTO"
      exit 1
    fi
    for m in runtime lto; do
      wasm-tools print $m.wasm > $m.wat
      if grep -qw try $m.wat; then
        echo "$m.wasm uses legacy exception handling"
        exit 1
      fi
    done
    touch $out
  ''
