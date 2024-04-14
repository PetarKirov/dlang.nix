# shellcheck shell=bash

dubInstallHook() {
    echo "Executing dubInstallHook"

    runHook preInstall

    mkdir -p "$out/bin"
    if [ -e "$pname" ]; then
        bin=$pname
    elif [ -e "bin/$pname" ]; then
        bin="bin/$pname"
    elif [ -e "$pname/$pname" ]; then
        bin="$pname/$pname"
    elif [ -e "bin/$pname/$pname" ]; then
        bin="bin/$pname/$pname"
    elif [ -e "$pname/bin/$pname" ]; then
        bin="$pname/bin/$pname"
    else
        if [ -z "${extraFiles-}" ]; then
            echo "EROOR: Could not find the binary to install, and no additional files were specified"
        else
            echo "WARNING: Could not find the binary to install, but additional files were specified"
        fi
    fi

    mkdir -p "$out/lib"
    cp -r *.a *.so *.so.* *.dylib "$out/lib"

    if [ -n "${bin-}" ]; then
        cp "$bin" "$out/bin"
    fi

    for f in $extraFiles; do
        fDir=$(dirname "$f")
        mkdir -p "$out/$fDir"
        cp "$f" "$fDir/$f"
    done

    runHook postInstall

    echo "Finished dubInstallHook"
}

if [ -z "${dontdubInstall-}" ] && [ -z "${installPhase-}" ]; then
    installPhase=dubInstallHook
fi
