# shellcheck shell=bash

dubInstallHook() {
    echo "Executing dubInstallHook"

    runHook preInstall

    mkdir -p "$out/bin"
    if [ -f "$pname" ]; then
        bin=$pname
    elif [ -f "bin/$pname" ]; then
        bin="bin/$pname"
    elif [ -f "$pname/$pname" ]; then
        bin="$pname/$pname"
    elif [ -f "bin/$pname/$pname" ]; then
        bin="bin/$pname/$pname"
    elif [ -f "$pname/bin/$pname" ]; then
        bin="$pname/bin/$pname"
    elif [ -f "build/$pname" ]; then
        bin="build/$pname"
    else
        if ls *.a *.so *.so.* *.dylib 1>/dev/null 2>&1; then
            echo "INFO: Could not find the binary to install, but found some libraries"
        elif [ -z "${extraFiles-}"  ]; then
            echo "ERROR: Could not find the binary to install, or any libraries, and no additional files were specified"
            exit 1
        else
            echo "WARNING: Could not find the binary to install, but additional files were specified"
        fi
    fi


    if [ -n "${bin-}" ]; then
        cp "$bin" "$out/bin"
    fi

    mkdir -p "$out/lib"
    cp -r *.a *.so *.so.* *.dylib "$out/lib" 2>/dev/null || true

    for f in $extraFiles; do
        fDir=$(dirname "$f")
        mkdir -p "$out/$fDir"
        cp "$f" "$fDir/$f"
    done

    runHook postInstall

    echo "Finished dubInstallHook"
}

if [ -z "${dontDubInstall-}" ] && [ -z "${installPhase-}" ]; then
    installPhase=dubInstallHook
fi
