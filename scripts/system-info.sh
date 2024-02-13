#!/usr/bin/env bash

set -euo pipefail

get_platform() {
  case "$(uname -s).$(uname -m)" in
    Linux.x86_64)
        export system=x86_64-linux
        export is_linux=true
        export is_darwin=false
        ;;
    Linux.i?86)
        export system=i686-linux
        export is_linux=true
        export is_darwin=false
        ;;
    Linux.aarch64)
        export system=aarch64-linux
        export is_linux=true
        export is_darwin=false
        ;;
    Linux.armv6l_linux)
        export system=armv6l-linux
        export is_linux=true
        export is_darwin=false
        ;;
    Linux.armv7l_linux)
        export system=armv7l-linux
        export is_linux=true
        export is_darwin=false
        ;;
    Darwin.x86_64)
        export system=x86_64-darwin
        export is_linux=false
        export is_darwin=true
        ;;
    Darwin.arm64|Darwin.aarch64)
        system=aarch64-darwin
        export is_linux=false
        export is_darwin=true
        ;;
    *) error "sorry, there is no binary distribution of Nix for your platform";;
  esac
}

get_nix_eval_worker_count() {
  if [[ -z "${MAX_WORKERS:-}" ]]; then
    available_parallelism="$(nproc)"
    export max_workers="$((available_parallelism < 8 ? available_parallelism : 8))"
  else
    export max_workers="$MAX_WORKERS"
  fi
}

get_available_memory_mb() {
  if [ "$is_darwin" = 'true' ]; then
    free_pages="$(vm_stat | grep 'Pages free:' | tr -s ' ' | cut -d ' ' -f 3 | tr -d '.')"
    inactive_pages="$(vm_stat | grep 'Pages inactive:' | tr -s ' ' | cut -d ' ' -f 3 | tr -d '.')"
    pages="$((free_pages + inactive_pages))"
    page_size="$(pagesize)"
    export max_memory_mb="${MAX_MEMORY:-$(((pages * page_size) / 1024 / 1024 ))}"
  else
    free="$(< /proc/meminfo grep MemFree | tr -s ' ' | cut -d ' ' -f 2)"
    cached="$(< /proc/meminfo grep Cached | grep -v SwapCached | tr -s ' ' | cut -d ' ' -f 2)"
    buffers="$(< /proc/meminfo grep Buffers | tr -s ' ' | cut -d ' ' -f 2)"
    shmem="$(< /proc/meminfo  grep Shmem: | tr -s ' ' | cut -d ' ' -f 2)"
    export max_memory_mb="${MAX_MEMORY:-$(((free + cached + buffers + shmem) / 1024 ))}"
  fi
}
