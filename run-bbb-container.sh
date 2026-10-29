#!/usr/bin/env bash
# Optional Debian container with libgpiod 1.6.3 + host gpiochip passthrough.
# Prefer ./scripts/run-rhel9-on-zorin.sh for the main lab.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${BBB_GPIO_IMAGE:-localhost/bbb-gpio:libgpiod-1.6.3}"
LIBGPIOD_VER="${LIBGPIOD_VER:-1.6.3}"

pick_runtime() {
  if [[ -n "${CONTAINER_RUNTIME:-}" ]]; then
    echo "$CONTAINER_RUNTIME"
    return
  fi
  if command -v podman >/dev/null 2>&1; then
    echo podman
  elif command -v docker >/dev/null 2>&1; then
    echo docker
  else
    echo "error: need podman or docker" >&2
    exit 1
  fi
}

RUNTIME="$(pick_runtime)"

usage() {
  cat <<EOF
Usage: $0 <build|run|shell|gpiodetect> [args...]

  build         Build image with libgpiod ${LIBGPIOD_VER}
  run [cmd...]  Run with all host /dev/gpiochip* devices passed through
  shell         Interactive shell (same device mounts)
  gpiodetect    Shortcut: run gpiodetect inside the container

Env:
  BBB_GPIO_IMAGE       default: $IMAGE
  LIBGPIOD_VER         default: $LIBGPIOD_VER
  CONTAINER_RUNTIME    podman|docker
  BBB_GPIO_PRIVILEGED  set to 1 to use --privileged instead of --device
EOF
}

device_args() {
  local c
  shopt -s nullglob
  local chips=(/dev/gpiochip*)
  if ((${#chips[@]} == 0)); then
    echo "error: no /dev/gpiochip* on host." >&2
    echo "  Create BBB-like chips first: sudo ./scripts/setup-gpio-mockup.sh" >&2
    exit 2
  fi
  echo "==> Passing host chips: ${chips[*]}" >&2
  if [[ "${BBB_GPIO_PRIVILEGED:-0}" == "1" ]]; then
    echo --privileged
    return
  fi
  for c in "${chips[@]}"; do
    printf '%s\n' --device="$c"
  done
  # RHEL9 SELinux: char devices often need this for non-privileged containers
  printf '%s\n' --security-opt label=disable
}

cmd_build() {
  echo "==> Building $IMAGE (libgpiod ${LIBGPIOD_VER}) with $RUNTIME"
  $RUNTIME build \
    --build-arg "LIBGPIOD_VER=${LIBGPIOD_VER}" \
    -t "$IMAGE" \
    -f "$ROOT/container/Containerfile" \
    "$ROOT/container"
}

cmd_run() {
  local args=()
  mapfile -t args < <(device_args)
  local run_cmd=("$@")
  if ((${#run_cmd[@]} == 0)); then
    run_cmd=(/usr/local/bin/bbb-gpio-entrypoint)
  fi
  echo "==> $RUNTIME run ${args[*]} $IMAGE ${run_cmd[*]}"
  exec $RUNTIME run --rm -it \
    "${args[@]}" \
    -v "$ROOT/tools:/opt/bbb-gpio/tools:ro" \
    "$IMAGE" \
    "${run_cmd[@]}"
}

case "${1:-}" in
  build) shift; cmd_build "$@" ;;
  run) shift; cmd_run "$@" ;;
  shell) shift; cmd_run /bin/bash ;;
  gpiodetect) shift; cmd_run gpiodetect "$@" ;;
  -h|--help|help|"") usage; [[ -n "${1:-}" ]] || exit 1 ;;
  *) echo "unknown command: $1" >&2; usage; exit 1 ;;
esac
