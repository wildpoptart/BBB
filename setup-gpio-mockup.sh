#!/usr/bin/env bash
# Create BeagleBone-like /dev/gpiochip* using gpio-mockup only (no gpio-sim).
# Real host chardevs for libgpiod 1.6.x (RHEL 9).
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

# Three 32-line chips (BBB-ish banks). Ranges: base,num  (base -1 = dynamic)
BANK_LINES="${GPIO_BANK_LINES:-32}"
NUM_BANKS="${GPIO_NUM_BANKS:-3}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

if ! modinfo gpio-mockup >/dev/null 2>&1; then
  die "gpio-mockup module not found on this kernel (modinfo gpio-mockup failed).
This kit does not use gpio-sim.
On Zorin/Ubuntu try: sudo apt install linux-modules-extra-\$(uname -r)
If you cannot load any GPIO kernel module, use the userspace mock instead:
  python3 tools/gpiod_usermock.py --demo"
fi

log "Removing any existing gpio-mockup"
modprobe -r gpio_mockup 2>/dev/null || true

# Build ranges: -1,32,-1,32,-1,32
ranges=()
for _ in $(seq 1 "$NUM_BANKS"); do
  ranges+=(-1,"$BANK_LINES")
done
range_csv=$(IFS=,; echo "${ranges[*]}")

log "Loading gpio-mockup gpio_mockup_ranges=${range_csv}"
modprobe gpio-mockup "gpio_mockup_ranges=${range_csv}" \
  || die "modprobe gpio-mockup failed (need --privileged + /lib/modules in the RHEL9 container)"

for i in $(seq 1 30); do
  if compgen -G '/dev/gpiochip*' >/dev/null; then
    break
  fi
  sleep 0.1
done

if ! compgen -G '/dev/gpiochip*' >/dev/null; then
  die "module loaded but no /dev/gpiochip* appeared"
fi

echo
log "Host chips for libgpiod 1.6.x:"
ls -l /dev/gpiochip*
if command -v gpiodetect >/dev/null 2>&1; then
  gpiodetect || true
  echo
  echo "libgpiod 1.x examples:"
  echo "  gpioset gpiochip0 0=1"
  echo "  gpioget gpiochip0 0"
  echo "  gpioinfo gpiochip0"
fi

cat <<EOF

Tear down later:
  sudo modprobe -r gpio_mockup

If modprobe is forbidden in your environment, skip this script and use:
  python3 tools/gpiod_usermock.py --demo
EOF
