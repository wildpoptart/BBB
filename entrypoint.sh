#!/bin/sh
# Default entry: show chip visibility, then exec user command if provided.
set -eu

echo "==> BeagleBone GPIO container (libgpiod ${LIBGPIOD_VER:-?})"
echo "==> /dev/gpiochip* inside container:"
if ls -l /dev/gpiochip* 2>/dev/null; then
  :
else
  echo "    (none) — pass --device=/dev/gpiochipN from the host"
  echo "    On RHEL9 also try: --security-opt label=disable"
fi

if command -v gpiodetect >/dev/null 2>&1; then
  echo "==> gpiodetect:"
  gpiodetect 2>&1 || echo "    gpiodetect failed (ioctl/open) — see docs/ioctl-container.md"
fi

if [ "$#" -eq 0 ]; then
  exec /bin/bash
fi
exec "$@"
