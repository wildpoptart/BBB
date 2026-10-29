#!/usr/bin/env bash
# Pass host /dev/gpiochip* (from gpio-mockup) into a container.
set -euo pipefail

IMAGE="${BBB_GPIO_IMAGE:-localhost/bone-gpio-rhel9:latest}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

shopt -s nullglob
chips=(/dev/gpiochip*)
if ((${#chips[@]} == 0)); then
  echo "missing /dev/gpiochip* — run: sudo $ROOT/scripts/setup-gpio-mockup.sh" >&2
  exit 1
fi

RUNTIME=podman
command -v podman >/dev/null 2>&1 || RUNTIME=docker

args=()
for c in "${chips[@]}"; do
  args+=(--device="$c")
done

exec "$RUNTIME" run --rm -it \
  "${args[@]}" \
  --security-opt label=disable \
  "$IMAGE" \
  sh -c 'ls -l /dev/gpiochip*; gpiodetect; gpioset gpiochip0 0=1; gpioget gpiochip0 0'
