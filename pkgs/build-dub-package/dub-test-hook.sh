# shellcheck shell=bash

dubTestHook() {
    echo "Executing dubTestHook"

    runHook preTest

    export HOME="/build"
    chmod -R +rw $HOME
    chown -R $(whoami) $HOME
    if ! @dub@ test  $dubTestFlags "${dubTestFlagsArray[@]}" $dubFlags "${dubFlagsArray[@]}"; then
        echo
        echo 'ERROR: `dub test` failed'
        echo

        exit 1
    fi

    runHook postTest

    echo "Finished dubTestHook"
}

if [ -z "${dontdubTest-}" ] && [ -z "${checkPhase-}" ]; then
    checkPhase=dubTestHook
    doCheck=true
fi