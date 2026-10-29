#!/usr/bin/env bash
# Build/run RHEL 9 BBB-GPIO lab on Zorin (libgpiod 1.6.3, gpio-mockup, no gpio-sim).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${BONE_GPIO_RHEL9_IMAGE:-localhost/bone-gpio-rhel9:latest}"
NAME="${BONE_GPIO_RHEL9_NAME:-bone-gpio-rhel9}"

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
    echo "error: install docker or podman on Zorin" >&2
    exit 1
  fi
}

RUNTIME="$(pick_runtime)"
KVER="$(uname -r)"

usage() {
  cat <<EOF
Usage: $0 <build|run|shell|smoke|usermock> [args...]

  build     Build RHEL 9 UBI image with libgpiod 1.6.3 + toolkit
  run       Privileged container; loads gpio-mockup (not gpio-sim)
  shell     Alias for run
  smoke     Smoke-test real /dev/gpiochip* via libgpiod 1.x
  usermock  Skip kernel modules; run in-process GPIO mock demo

Env:
  BONE_GPIO_RHEL9_IMAGE      default: $IMAGE
  BBB_SKIP_GPIO_MOCKUP=1     skip mockup in entrypoint
  CONTAINER_RUNTIME          docker|podman

Host (Zorin):
  Docker/Podman
  gpio-mockup module:  modinfo gpio-mockup
    (sudo apt install linux-modules-extra-\$(uname -r) if missing)
EOF
}

host_preflight() {
  echo "==> Host kernel: $KVER"
  if [[ ! -d "/lib/modules/$KVER" ]]; then
    echo "error: /lib/modules/$KVER missing on host" >&2
    exit 1
  fi
  if command -v modinfo >/dev/null 2>&1; then
    if modinfo gpio-mockup >/dev/null 2>&1; then
      echo "==> gpio-mockup module found on host"
    else
      echo "!! gpio-mockup not found. Try: sudo apt install linux-modules-extra-$KVER"
      echo "   Or use: $0 usermock   (no kernel GPIO module)"
    fi
  fi
}

cmd_build() {
  echo "==> Building $IMAGE (libgpiod 1.6.3, no gpio-sim)"
  $RUNTIME build \
    -f "$ROOT/container/Containerfile.rhel9" \
    -t "$IMAGE" \
    "$ROOT"
}

cmd_run() {
  host_preflight
  $RUNTIME rm -f "$NAME" >/dev/null 2>&1 || true
  local -a cmd=("$@")
  echo "==> $RUNTIME run --privileged $IMAGE ${cmd[*]:-<bash>}"
  exec $RUNTIME run \
    --name "$NAME" \
    --privileged \
    --rm \
    -it \
    -e "LIBGPIOD_VER=1.6.3" \
    -e "BBB_SKIP_GPIO_MOCKUP=${BBB_SKIP_GPIO_MOCKUP:-0}" \
    -v /lib/modules:/lib/modules:ro \
    -v /dev:/dev \
    "$IMAGE" \
    "${cmd[@]}"
}

case "${1:-}" in
  build) shift; cmd_build "$@" ;;
  run) shift; cmd_run "$@" ;;
  shell) shift; cmd_run /bin/bash ;;
  smoke) shift; cmd_run /opt/bone-gpio-kit/examples/smoke-test.sh ;;
  usermock)
    shift
    BBB_SKIP_GPIO_MOCKUP=1 cmd_run python3 /opt/bone-gpio-kit/tools/gpiod_usermock.py --demo
    ;;
  -h|--help|help|"") usage; [[ -n "${1:-}" ]] || exit 1 ;;
  *) echo "unknown: $1" >&2; usage; exit 1 ;;
esac
