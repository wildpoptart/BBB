#!/usr/bin/env bash
# RHEL9 BBB-GPIO lab: libgpiod 1.6.3 + gpio-mockup (no gpio-sim).
set -euo pipefail

ROOT="${BONE_GPIO_ROOT:-/opt/bone-gpio-kit}"
SKIP_MOCKUP="${BBB_SKIP_GPIO_MOCKUP:-0}"

echo "==> bone-gpio-kit RHEL 9 (libgpiod ${LIBGPIOD_VER:-1.6.3}, no gpio-sim)"
echo "    root: $ROOT"
echo "    libgpiod: $(gpiodetect --version 2>/dev/null || echo missing)"
echo "    kernel (host): $(uname -r)"

if [[ ! -d /lib/modules/$(uname -r) ]]; then
  echo "!! /lib/modules/$(uname -r) not mounted — mockup modprobe will fail."
  echo "   Start with: ./scripts/run-rhel9-on-zorin.sh"
fi

if [[ "$SKIP_MOCKUP" != "1" ]]; then
  if [[ "${EUID}" -ne 0 ]]; then
    echo "!! not root; cannot modprobe gpio-mockup"
  else
    echo "==> Setting up gpio-mockup (BBB-like chips)"
    if ! "$ROOT/scripts/setup-gpio-mockup.sh"; then
      echo "!! gpio-mockup setup failed — kernel module unavailable or blocked."
      echo "   Userspace-only fallback (no /dev/gpiochip):"
      echo "     python3 $ROOT/tools/gpiod_usermock.py --demo"
    fi
  fi
else
  echo "==> Skipping gpio-mockup (BBB_SKIP_GPIO_MOCKUP=1)"
fi

echo "==> /dev/gpiochip* in this container:"
ls -l /dev/gpiochip* 2>/dev/null || echo "    (none — use usermock or fix mockup)"

if command -v gpiodetect >/dev/null 2>&1; then
  gpiodetect 2>/dev/null || true
fi

cat <<EOF

Ready (libgpiod 1.x CLI):
  diagnose-gpio
  setup-gpio-mockup
  gpioset gpiochip0 0=1
  gpioget gpiochip0 0
  python3 $ROOT/tools/gpiod_usermock.py --demo

EOF

if [[ "$#" -eq 0 ]]; then
  exec /bin/bash
fi
exec "$@"
