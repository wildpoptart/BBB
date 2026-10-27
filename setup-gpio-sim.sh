#!/usr/bin/env bash
# Create BeagleBone-like /dev/gpiochip* on RHEL9 via gpio-sim (or gpio-mockup).
# These are real host chardevs — apps/containers use them like BBB hardware.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

SIM_NAME="${GPIO_SIM_NAME:-bbb}"
# BBB-ish: three 32-line banks (enough for P8/P9-oriented apps)
BANK0_LINES="${GPIO_BANK0_LINES:-32}"
BANK1_LINES="${GPIO_BANK1_LINES:-32}"
BANK2_LINES="${GPIO_BANK2_LINES:-32}"
CONFIGFS="${CONFIGFS_MOUNT:-/sys/kernel/config}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Approximate P8/P9 header names for look-ups during development.
# Not a full pinmux map — enough for "request by name" app testing.
p8_name() {
  local i="$1"
  # P8_1/2 = GND on real BBB; we still label lines for sim apps
  printf 'P8_%d' "$((i + 1))"
}

p9_name() {
  local i="$1"
  printf 'P9_%d' "$((i + 1))"
}

ensure_configfs() {
  mkdir -p "$CONFIGFS"
  if ! mountpoint -q "$CONFIGFS"; then
    mount -t configfs configfs "$CONFIGFS" || die "cannot mount configfs at $CONFIGFS"
  fi
}

teardown_sim() {
  local base="$1"
  [[ -d "$base" ]] || return 0
  log "Tearing down existing sim at $base"
  if [[ -f "$base/live" ]]; then
    echo 0 > "$base/live" || true
  fi
  local b
  for b in "$base"/*/; do
    [[ -d "$b" ]] || continue
    # clear line dirs if present
    local l
    for l in "$b"/line*/; do
      [[ -d "$l" ]] && rmdir "$l" 2>/dev/null || true
    done
    rmdir "$b" 2>/dev/null || true
  done
  rmdir "$base" 2>/dev/null || true
}

write_bank_names() {
  local bank="$1"
  local prefix="$2"   # p8 | p9 | gpio
  local n="$3"
  local i name
  for i in $(seq 0 $((n - 1))); do
    case "$prefix" in
      p8) name="$(p8_name "$i")" ;;
      p9) name="$(p9_name "$i")" ;;
      *)  name="GPIO${prefix}_${i}" ;;
    esac
    if [[ -d "$bank/line${i}" && -f "$bank/line${i}/name" ]]; then
      printf '%s' "$name" > "$bank/line${i}/name" || true
    elif [[ -f "$bank/line${i}/name" ]]; then
      printf '%s' "$name" > "$bank/line${i}/name" || true
    else
      # Some kernels need the lineN dir created first
      mkdir -p "$bank/line${i}" 2>/dev/null || true
      if [[ -f "$bank/line${i}/name" ]]; then
        printf '%s' "$name" > "$bank/line${i}/name" || true
      fi
    fi
  done
}

setup_gpio_sim() {
  log "Loading gpio-sim"
  modprobe gpio-sim || return 1
  ensure_configfs
  [[ -d "$CONFIGFS/gpio-sim" ]] || return 1

  local base="$CONFIGFS/gpio-sim/$SIM_NAME"
  teardown_sim "$base"

  log "Creating BBB-like gpio-sim '$SIM_NAME' (3 banks × 32 lines)"
  mkdir -p "$base/bank0" "$base/bank1" "$base/bank2"

  echo "$BANK0_LINES" > "$base/bank0/num_lines"
  echo "gpio-0-31" > "$base/bank0/label" 2>/dev/null || true
  write_bank_names "$base/bank0" p8 "$BANK0_LINES"

  echo "$BANK1_LINES" > "$base/bank1/num_lines"
  echo "gpio-32-63" > "$base/bank1/label" 2>/dev/null || true
  write_bank_names "$base/bank1" p9 "$BANK1_LINES"

  echo "$BANK2_LINES" > "$base/bank2/num_lines"
  echo "gpio-64-95" > "$base/bank2/label" 2>/dev/null || true
  write_bank_names "$base/bank2" gpio2 "$BANK2_LINES"

  echo 1 > "$base/live"

  local i
  for i in $(seq 1 30); do
    if compgen -G '/dev/gpiochip*' >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

setup_gpio_mockup() {
  log "Falling back to gpio-mockup (older RHEL 9 kernels without gpio-sim)"
  modprobe -r gpio_mockup 2>/dev/null || true
  # Three chips, 32 lines each
  modprobe gpio-mockup \
    gpio_mockup_ranges=-1,32,-1,32,-1,32 \
    || return 1
  local i
  for i in $(seq 1 30); do
    if compgen -G '/dev/gpiochip*' >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

log "Emulating BeagleBone-style GPIO on this host"
if setup_gpio_sim; then
  log "gpio-sim is live"
elif setup_gpio_mockup; then
  log "gpio-mockup is live (line names may be unnamed)"
else
  die "Neither gpio-sim nor gpio-mockup produced /dev/gpiochip*. Install/enable the module for this kernel, or check: modinfo gpio-sim"
fi

echo
log "Host chips (use these from your app / container):"
ls -l /dev/gpiochip* || true
if command -v gpiodetect >/dev/null 2>&1; then
  gpiodetect || true
fi
if command -v gpioinfo >/dev/null 2>&1; then
  echo
  gpioinfo 2>/dev/null | head -n 40 || true
fi

cat <<EOF

These are real host /dev/gpiochip* nodes backed by the kernel simulator.
Your code should use libgpiod against them the same way as on a BBB.

Next:
  ./scripts/diagnose-gpio.sh
  ./scripts/run-bbb-container.sh build
  ./scripts/run-bbb-container.sh run

To tear down gpio-sim later:
  echo 0 | sudo tee /sys/kernel/config/gpio-sim/${SIM_NAME}/live
  sudo rmdir /sys/kernel/config/gpio-sim/${SIM_NAME}/bank* 2>/dev/null || true
  sudo rmdir /sys/kernel/config/gpio-sim/${SIM_NAME}
EOF
