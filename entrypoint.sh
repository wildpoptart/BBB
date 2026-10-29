#!/bin/sh
set -eu
echo "==> libgpiod ${LIBGPIOD_VER:-1.6.3} container"
echo "==> /dev/gpiochip*:"
ls -l /dev/gpiochip* 2>/dev/null || echo "    (none) — pass host chips or use gpio-mockup on the host"
if command -v gpiodetect >/dev/null 2>&1; then
  gpiodetect 2>&1 || true
fi
if [ "$#" -eq 0 ]; then
  exec /bin/bash
fi
exec "$@"
