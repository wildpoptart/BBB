#!/usr/bin/env bash
# Smoke-test BBB-like chips with libgpiod 1.x CLI (no gpio-sim).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! compgen -G '/dev/gpiochip*' >/dev/null; then
  echo "No /dev/gpiochip* — run: sudo $ROOT/scripts/setup-gpio-mockup.sh" >&2
  echo "Or userspace-only: python3 $ROOT/tools/gpiod_usermock.py --demo" >&2
  exit 1
fi

echo "==> chips"
ls -l /dev/gpiochip*

if command -v gpiodetect >/dev/null 2>&1; then
  echo "==> gpiodetect ($(gpiodetect --version 2>/dev/null || true))"
  gpiodetect
else
  python3 "$ROOT/tools/gpio_probe.py" /dev/gpiochip0
  exit 0
fi

# libgpiod 1.x: gpioset <chip> <offset>=<value>
if command -v gpioset >/dev/null 2>&1 && command -v gpioget >/dev/null 2>&1; then
  echo "==> set/get line 0 on gpiochip0 (libgpiod 1.x syntax)"
  gpioset gpiochip0 0=1
  gpioget gpiochip0 0
  gpioset gpiochip0 0=0
  gpioget gpiochip0 0
  echo "smoke-test ok"
else
  python3 "$ROOT/tools/gpio_probe.py" /dev/gpiochip0
fi
