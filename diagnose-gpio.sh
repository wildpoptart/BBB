#!/usr/bin/env bash
# Diagnose BBB-like host GPIO on RHEL9 (gpio-sim backed /dev/gpiochip*).
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

bold "Host GPIO character devices"
shopt -s nullglob
chips=(/dev/gpiochip*)
if ((${#chips[@]} == 0)); then
  warn "No /dev/gpiochip* on this host"
  info "Create BBB-like chips: sudo ./scripts/setup-gpio-sim.sh"
else
  for c in "${chips[@]}"; do
    majmin=$(stat -c '%t:%T' "$c" 2>/dev/null || echo '?')
    mode=$(stat -c '%a %U:%G' "$c" 2>/dev/null || echo '?')
    ok "$c  maj:min(hex)=$majmin  mode=$mode"
  done
fi

bold "gpio-sim / gpio-mockup"
if command -v lsmod >/dev/null 2>&1; then
  if lsmod | grep -q '^gpio_sim'; then
    ok "gpio_sim loaded"
  elif lsmod | grep -q '^gpio_mockup'; then
    ok "gpio_mockup loaded"
  else
    info "neither gpio_sim nor gpio_mockup loaded"
  fi
fi
if [[ -d /sys/kernel/config/gpio-sim ]]; then
  for d in /sys/kernel/config/gpio-sim/*; do
    [[ -d "$d" ]] || continue
    live="?"
    [[ -f "$d/live" ]] && live=$(cat "$d/live" 2>/dev/null || echo '?')
    info "configfs $(basename "$d") live=$live"
  done
fi

bold "Host libgpiod tools"
if command -v gpiodetect >/dev/null 2>&1; then
  info "gpiodetect: $(gpiodetect --version 2>/dev/null || echo present)"
  if ((${#chips[@]} > 0)) && gpiodetect 2>/dev/null; then
    ok "gpiodetect succeeded on host"
  elif ((${#chips[@]} > 0)); then
    warn "gpiodetect failed on host"
  fi
else
  info "gpiodetect not installed (optional; container has it)"
fi

if command -v python3 >/dev/null 2>&1; then
  bold "Python chardev probe (host)"
  root="$(cd "$(dirname "$0")/.." && pwd)"
  if ((${#chips[@]} > 0)); then
    if python3 "$root/tools/gpio_probe.py" "${chips[0]}"; then
      ok "gpio_probe.py open+ioctl ok on ${chips[0]}"
    else
      warn "gpio_probe.py failed on ${chips[0]}"
    fi
  else
    info "skip probe (no chips)"
  fi
fi

bold "SELinux (RHEL)"
if command -v getenforce >/dev/null 2>&1; then
  enc=$(getenforce 2>/dev/null || echo unknown)
  info "getenforce: $enc"
  if [[ "$enc" == "Enforcing" ]]; then
    info "Container open/ioctl fails with AVC? use --security-opt label=disable"
  fi
else
  info "SELinux tools not present"
fi

bold "Container runtime"
runtime=""
if command -v podman >/dev/null 2>&1; then
  runtime=podman
  ok "podman: $(podman --version)"
elif command -v docker >/dev/null 2>&1; then
  runtime=docker
  ok "docker: $(docker --version)"
else
  info "No podman/docker (OK if you develop on the host against the chips)"
fi

if [[ -n "$runtime" ]] && ((${#chips[@]} > 0)); then
  bold "Hint: container passthrough"
  info "./scripts/run-bbb-container.sh run"
fi

bold "Summary"
if ((${#chips[@]} == 0)); then
  warn "No host gpiochip — run: sudo ./scripts/setup-gpio-sim.sh"
  exit 2
fi
ok "Host has ${#chips[@]} gpiochip device(s) for BBB-like development."
info "Point libgpiod at these devices; use the container only if you need Debian 2.2.1 userspace."
exit 0
