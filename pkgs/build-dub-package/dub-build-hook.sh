# shellcheck shell=bash

dubBuildHook() {
    echo "Executing dubBuildHook"

    runHook preBuild

    export HOME="/build"
    chmod -R +rw $HOME
    chown -R $(whoami) $HOME
    if ! @dub@ build  $dubBuildFlags "${dubBuildFlagsArray[@]}" $dubFlags "${dubFlagsArray[@]}"; then
        echo
        echo 'ERROR: `dub build` failed'
        echo

        exit 1
    fi

    runHook postBuild

    echo "Finished dubBuildHook"
}

if [ -z "${dontdubBuild-}" ] && [ -z "${buildPhase-}" ]; then
    buildPhase=dubBuildHook
fi
