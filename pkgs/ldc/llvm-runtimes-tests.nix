# The all-LLVM runtime profile's interoperation scenarios (Sparkles' toolchain
# specification, TC19), built by ./with-llvm-runtimes.nix's LDC and its clang:
#
# - a D exception thrown through a C++ frame is caught in D;
# - a C++ exception thrown through a D frame, whose `scope (exit)` runs, is
#   caught in C++;
# - an uncaught D exception prints a stack trace that resolves its D frames
#   to file and line;
# - the program needs neither libgcc_s nor libstdc++, and loads neither;
# - a link that asks for the shared druntime and Phobos, as dub's unittest
#   build types do, links them statically all the same, and its exported
#   unwinder serves the stack trace;
# - a link by lld names a library from another store path on its RUNPATH.
{
  runCommand,
  lib,
  binutils,
  zlib,
  ldc,
}:
runCommand "ldc-llvm-runtimes-tests"
  {
    nativeBuildInputs = [
      ldc
      ldc.cc
      binutils
    ];
  }
  ''
    cat > interop.cpp <<'EOF'
    #include <stdexcept>

    extern "C" void d_throws();
    extern "C" void d_calls_cpp_thrower();

    // A D exception unwinds through this frame.
    extern "C" void cpp_calls_d() { d_throws(); }

    extern "C" void cpp_throws() { throw std::runtime_error("from C++"); }

    // A C++ exception unwinds through a D frame back to here.
    extern "C" int cpp_catches_through_d() {
      try {
        d_calls_cpp_thrower();
      } catch (const std::runtime_error &) {
        return 1;
      }
      return 0;
    }
    EOF

    cat > interop.d <<'EOF'
    module interop;

    import core.stdc.stdio : printf;

    extern (C) void cpp_calls_d();
    extern (C) void cpp_throws();
    extern (C) int cpp_catches_through_d();

    __gshared bool cleanedUp;

    extern (C) void d_throws() { throw new Exception("from D"); }

    extern (C) void d_calls_cpp_thrower()
    {
        scope (exit) cleanedUp = true;
        cpp_throws();
    }

    void deep(int n) { if (n == 0) throw new Exception("uncaught"); deep(n - 1); }

    int main(string[] args)
    {
        if (args.length > 1)
            deep(3);
        string caught;
        try cpp_calls_d(); catch (Exception e) caught = e.msg;
        const cppCaught = cpp_catches_through_d();
        printf("D caught: %.*s; C++ caught: %d; scope(exit) ran: %d\n",
            cast(int) caught.length, caught.ptr, cppCaught, cleanedUp);
        return 0;
    }
    EOF

    c++ -c interop.cpp -o cpp.o
    ldc2 -g interop.d cpp.o -of=interop

    expected="D caught: from D; C++ caught: 1; scope(exit) ran: 1"
    actual=$(./interop)
    if [ "$actual" != "$expected" ]; then
      echo "expected '$expected', got '$actual'"
      exit 1
    fi

    if ./interop uncaught 2> trace.txt; then
      echo "the uncaught exception did not fail the program"
      exit 1
    fi
    cat trace.txt
    grep -q '^interop.d:[0-9]' trace.txt || { echo "no D frame in the stack trace"; exit 1; }

    readelf -d interop | tee dynamic.txt
    if grep -E 'libgcc_s|libstdc\+\+|libunwind|libc\+\+' dynamic.txt; then
      echo "the program needs a runtime library dynamically"
      exit 1
    fi
    LD_DEBUG=libs ./interop 2> loaded.txt > /dev/null
    if grep -E 'libgcc_s|libstdc\+\+' loaded.txt; then
      echo "the program loaded a GCC runtime"
      exit 1
    fi

    ldc2 -g --link-defaultlib-shared -L--export-dynamic interop.d cpp.o -of=interop-shared
    readelf -d interop-shared | tee dynamic-shared.txt
    if grep -E 'libgcc_s|libdruntime|libphobos' dynamic-shared.txt; then
      echo "-link-defaultlib-shared linked a shared runtime"
      exit 1
    fi
    [ "$(./interop-shared)" = "$expected" ] || { echo "interop-shared failed"; exit 1; }
    if ./interop-shared uncaught 2> trace-shared.txt; then
      echo "the uncaught exception did not fail the program"
      exit 1
    fi
    grep -q '^interop.d:[0-9]' trace-shared.txt || { echo "no D frame in the stack trace"; exit 1; }

    cat > z.d <<'EOF'
    extern (C) const(char)* zlibVersion();
    extern (C) int puts(const(char)*);
    void main() { puts(zlibVersion()); }
    EOF
    ldc2 --linker=lld z.d -L-L${lib.getLib zlib}/lib -L-lz -of=z-lld
    readelf -d z-lld | grep RUNPATH | grep -q '${lib.getLib zlib}/lib'
    ./z-lld
    touch $out
  ''
