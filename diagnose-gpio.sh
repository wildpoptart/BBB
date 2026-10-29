#!/usr/bin/env bash
# Diagnose BBB-like host GPIO for libgpiod 1.6.x (gpio-mockup; no gpio-sim).
set -euo pipefail

bold() { printf '\n==> %s\n' "$*"; }
ok()   { printf '  [ok] %s\n' "$*"; }
warn() { printf '  [!!] %s\n' "$*"; }
info() { printf '  --  %s\n' "$*"; }

bold "Kernel / OS"
uname -a
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "OS: ${PRETTY_NAME:-unknown}"
fi
info "arch: $(uname -m)"

bold "libgpiod (expect 1.6.x)"
if command -v gpiodetect >/dev/null 2>&1; then
  ver=$(gpiodetect --version 2>/dev/null || echo present)
  info "$ver"
  if echo "$ver" | grep -qE '2\.'; then
    warn "This kit targets libgpiod 1.6.3; you have 2.x tools (CLI flags differ)"
  fi
else
  info "gpiodetect not installed"
fi

bold "Host GPIO character devices"
shopt -s nullglob
chips=(/dev/gpiochip*)
if ((${#chips[@]} == 0)); then
  warn "No /dev/gpiochip*"
  info "Create with: sudo ./scripts/setup-gpio-mockup.sh"
  info "Or userspace mock: python3 tools/gpiod_usermock.py --demo"
else
  for c in "${chips[@]}"; do
    majmin=$(stat -c '%t:%T' "$c" 2>/dev/null || echo '?')
    mode=$(stat -c '%a %U:%G' "$c" 2>/dev/null || echo '?')
    ok "$c  maj:min(hex)=$majmin  mode=$mode"
  done
fi

bold "gpio-mockup (gpio-sim is not used)"
if command -v lsmod >/dev/null 2>&1; then
  if lsmod | grep -q '^gpio_mockup'; then
    ok "gpio_mockup loaded"
  else
    info "gpio_mockup not loaded"
  fi
  if lsmod | grep -q '^gpio_sim'; then
    warn "gpio_sim is loaded but this kit does not use it"
  fi
fi
if command -v modinfo >/dev/null 2>&1; then
  if modinfo gpio-mockup >/dev/null 2>&1; then
    ok "gpio-mockup module available on this kernel"
  else
    warn "gpio-mockup not in this kernel — use tools/gpiod_usermock.py"
  fi
fi

if command -v python3 >/dev/null 2>&1; then
  bold "Python chardev probe / usermock"
  root="$(cd "$(dirname "$0")/.." && pwd)"
  if ((${#chips[@]} > 0)); then
    if python3 "$root/tools/gpio_probe.py" "${chips[0]}"; then
      ok "gpio_probe.py ok on ${chips[0]}"
    else
      warn "gpio_probe.py failed on ${chips[0]}"
    fi
  else
    info "no chips — running usermock demo"
    python3 "$root/tools/gpiod_usermock.py" --demo || true
  fi
fi

bold "SELinux (RHEL)"
if command -v getenforce >/dev/null 2>&1; then
  info "getenforce: $(getenforce 2>/dev/null || echo unknown)"
else
  info "SELinux tools not present"
fi

bold "Summary"
if ((${#chips[@]} == 0)); then
  warn "No /dev/gpiochip* — mockup not loaded, or use usermock for logic-only tests"
  exit 2
fi
ok "Host has ${#chips[@]} gpiochip device(s) for libgpiod 1.6.x"
info "1.x CLI: gpioset gpiochip0 0=1   /   gpioget gpiochip0 0"
exit 0
