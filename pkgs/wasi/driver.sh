#!@shell@
# @target@-@exe@: the fork's clang for one WASI preview (./default.nix), with
# its sysroot and resource directory, and WebAssembly exceptions in the
# standardized encoding (`exnref`), the only one the sysroot is built for.

link=1
compile=0
for arg in "$@"; do
  case "$arg" in
    -c | -S | -E | -M | -MM | -fsyntax-only) link=0 compile=1 ;;
    -*) ;;
    *.c | *.C | *.cc | *.cp | *.cpp | *.cxx | *.c++ | *.i | *.ii | *.m | *.mm | *.s | *.S) compile=1 ;;
  esac
done

# `-fwasm-exceptions` goes to every step (a link needs it to pick the
# exception-handling libraries); the encoding is a code-generation option,
# which a link-only command would report as unused.
flags=(-fwasm-exceptions)
if [ "$compile" = 1 ]; then
  flags+=(-mllvm -wasm-use-legacy-eh=false)
fi
# wasm-ld generates code itself for bitcode input, which a link may hold
# whether or not it says `-flto` (LDC passes LTO objects and archives without
# it), so every link names the encoding too; wasm-ld ignores it otherwise.
# Joined (`--mllvm=`): wasm-component-ld forwards it only in that spelling.
if [ "$link" = 1 ]; then
  flags+=(-Wl,--mllvm=-wasm-use-legacy-eh=false)
fi

# C++ and D exceptions unwind through libunwind. Only a link may name it, for
# the same reason.
extra=()
if [ "$link" = 1 ]; then
  extra=(-lunwind)
fi

exec @clang@/bin/@exe@ --target=@target@ --sysroot=@sysroot@ \
  -resource-dir=@resourceDir@ -B@libexec@ "${flags[@]}" \
  "$@" "${extra[@]}"
