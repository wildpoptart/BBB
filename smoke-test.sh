#!/usr/bin/env bash
# Smoke-test BBB-like host GPIO created by setup-gpio-sim.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! compgen -G '/dev/gpiochip*' >/dev/null; then
  echo "No /dev/gpiochip* — run: sudo $ROOT/scripts/setup-gpio-sim.sh" >&2
  exit 1
fi

echo "==> chips"
ls -l /dev/gpiochip*

if command -v gpiodetect >/dev/null 2>&1; then
  echo "==> gpiodetect"
  gpiodetect
else
  echo "==> gpiodetect not installed; using gpio_probe.py"
  python3 "$ROOT/tools/gpio_probe.py" /dev/gpiochip0
fi

# libgpiod 2.x CLI if present
if command -v gpioset >/dev/null 2>&1 && command -v gpioget >/dev/null 2>&1; then
  echo "==> set/get line 0 on gpiochip0"
  # Prefer name if present; fall back to offset
  if gpioinfo gpiochip0 2>/dev/null | grep -q 'P8_3'; then
    gpioset -c gpiochip0 -t 0 P8_3=1
    gpioget -c gpiochip0 P8_3
    gpioset -c gpiochip0 -t 0 P8_3=0
  else
    gpioset -c gpiochip0 -t 0 0=1
    gpioget -c gpiochip0 0
    gpioset -c gpiochip0 -t 0 0=0
  fi
  echo "smoke-test ok"
else
  echo "==> install libgpiod-utils for set/get, or use the container:"
  echo "    ./scripts/run-bbb-container.sh run gpioset -c gpiochip0 -t 0 0=1"
  python3 "$ROOT/tools/gpio_probe.py" /dev/gpiochip0
  echo "probe ok (CLI tools not on host)"
fi
