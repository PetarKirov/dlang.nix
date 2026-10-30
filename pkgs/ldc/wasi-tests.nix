# D programs compiled for one WASI preview by an LDC from ./with-wasi.nix and
# run under wasmtime: module constructors, the GC, and exceptions; then the
# same C library call with and without link-time optimization, where the LTO
# build must have inlined it from the sysroot's LTO libc (Sparkles' toolchain
# specification, TCW3), and no legacy exception-handling instruction may
# survive the link. On preview 1, a reactor (TCW7) whose `_initialize` runs
# its module constructor before its export is called. On preview 2 and 3, the
# same reactor as a library component exporting a WIT world (TCW7): no
# `wasi:cli/run`, and its start function, which wit-component points at
# `_initialize`, runs the module constructors exactly once, before the first
# export call; a command component composed onto it calls the export twice in
# one instance and sees the constructors ran once.
{
  lib,
  runCommand,
  wasmtime,
  wasm-tools,
  wac-cli,
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
  reactor = writeText "reactor.d" ''
    module reactor;

    int initialized;
    static this() { initialized = 42; }

    extern (C) int answer()
    {
        auto xs = new int[](1000);
        xs[$ - 1] = initialized;
        return xs[$ - 1];
    }
  '';
  component = writeText "component.d" ''
    module component;

    int initialized;
    int ctorRuns;
    int answered;
    static this() { initialized = 42; ++ctorRuns; }

    extern (C) int answer()
    {
        auto xs = new int[](1000);
        xs[$ - 1] = initialized;
        ++answered;
        return xs[$ - 1];
    }

    // How often the module constructors ran, times 100, plus the calls so far.
    extern (C) int calls() => ctorRuns * 100 + answered;
  '';
  componentWit = writeText "component.wit" ''
    package sparkles:probe;

    world probe {
        export answer: func() -> s32;
        export calls: func() -> s32;
    }
  '';
  # Calls the component's exports from one instance.
  caller = writeText "caller.d" ''
    module caller;

    import core.stdc.stdio : printf;
    import ldc.attributes : llvmAttr;

    @llvmAttr("wasm-import-module", "$root") @llvmAttr("wasm-import-name", "answer")
    extern (C) int probeAnswer();
    @llvmAttr("wasm-import-module", "$root") @llvmAttr("wasm-import-name", "calls")
    extern (C) int probeCalls();

    void main()
    {
        const a = probeAnswer();
        const b = probeAnswer();
        printf("answer %d %d, calls %d\n", a, b, probeCalls());
    }
  '';
  callerWit = writeText "caller.wit" ''
    package sparkles:probe-caller;

    world caller {
        import answer: func() -> s32;
        import calls: func() -> s32;
    }
  '';
in
runCommand "ldc-wasi-tests-${target}"
  {
    nativeBuildInputs = [
      ldc
      wasmtime
      wasm-tools
      wac-cli
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
    ${lib.optionalString (target == "wasm32-wasip1") ''
      ldc2 -mtriple=${target} -mexec-model=reactor ${reactor} \
        -L--export=answer -of=reactor.wasm
      wasm-tools print reactor.wasm > reactor.wat
      grep -q '(export "_initialize"' reactor.wat || { echo "reactor.wasm exports no _initialize"; exit 1; }
      if grep -q '(export "_start"' reactor.wat; then
        echo "reactor.wasm exports _start"
        exit 1
      fi
      expect "$(run --invoke answer reactor.wasm)" 42
    ''}
    ${lib.optionalString (target != "wasm32-wasip1") ''
      ldc2 -mtriple=${target} -mexec-model=reactor ${component} \
        -L--component-type=${componentWit} -L--export=answer -L--export=calls \
        -of=component.wasm
      wasm-tools component wit component.wasm > component.wit
      for f in answer calls; do
        grep -q "export $f: func() -> s32;" component.wit || { echo "component.wasm does not export $f"; exit 1; }
      done
      if grep -q 'export wasi:cli/run' component.wit; then
        echo "component.wasm exports wasi:cli/run"
        exit 1
      fi
      expect "$(run --invoke 'answer()' component.wasm)" 42
      expect "$(run --invoke 'calls()' component.wasm)" 100
      ldc2 -mtriple=${target} ${caller} -L--component-type=${callerWit} -of=caller.wasm
      wac plug caller.wasm --plug component.wasm -o composed.wasm
      expect "$(run composed.wasm)" "answer 42 42, calls 102"
    ''}
    touch $out
  ''
