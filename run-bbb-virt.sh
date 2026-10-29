#!/usr/bin/env bash
# Boot a Debian armhf "BeagleBone-like" lab under qemu-system-arm -M virt.
# This is full-system emulation (not binfmt qemu-user).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${BBB_VIRT_DIR:-$HOME/bbb-virt}"
IMAGE_URL="${BBB_VIRT_IMAGE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-armhf.qcow2}"
DISK="${BBB_VIRT_DISK:-$WORK/debian-armhf.qcow2}"
SEED="${WORK}/seed.iso"
MEM="${BBB_VIRT_MEM:-1G}"
SSH_PORT="${BBB_VIRT_SSH_PORT:-2222}"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing $1 — install qemu-system-arm / cloud-image-utils / wget"; }

usage() {
  cat <<EOF
Usage: $0 [fetch|seed|run|ssh|help]

  fetch  Download Debian armhf cloud image into $WORK
  seed   Build cloud-init seed (user debian / pass debian, SSH)
  run    Start qemu-system-arm -M virt (nographic)
  ssh    ssh into guest (localhost:$SSH_PORT)

Env: BBB_VIRT_DIR BBB_VIRT_DISK BBB_VIRT_MEM BBB_VIRT_SSH_PORT BBB_VIRT_IMAGE_URL
EOF
}

cmd_fetch() {
  need wget
  need qemu-img
  mkdir -p "$WORK"
  if [[ ! -f "$DISK" ]]; then
    local tmp="$WORK/debian-armhf.qcow2.download"
    echo "==> downloading $IMAGE_URL"
    wget -O "$tmp" "$IMAGE_URL"
    mv "$tmp" "$DISK"
    qemu-img resize "$DISK" 8G
  else
    echo "==> using existing $DISK"
  fi
}

cmd_seed() {
  need cloud-localds
  mkdir -p "$WORK/seed"
  cat >"$WORK/seed/user-data" <<'EOF'
#cloud-config
users:
  - name: debian
    plain_text_passwd: debian
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
ssh_pwauth: true
chpasswd:
  expire: false
package_update: true
packages:
  - build-essential
  - gpiod
  - libgpiod-dev
  - kmod
runcmd:
  - modprobe gpio-mockup gpio_mockup_ranges=-1,32,-1,32,-1,32 || true
EOF
  cat >"$WORK/seed/meta-data" <<EOF
instance-id: bbb-virt-1
local-hostname: bbb-virt
EOF
  cloud-localds "$SEED" "$WORK/seed/user-data" "$WORK/seed/meta-data"
  echo "==> wrote $SEED"
}

cmd_run() {
  need qemu-system-arm
  [[ -f "$DISK" ]] || die "no disk — run: $0 fetch"
  [[ -f "$SEED" ]] || cmd_seed

  echo "==> qemu-system-arm -M virt (SSH host port $SSH_PORT → guest 22)"
  echo "    login: debian / debian   |  Ctrl-A X to quit"
  echo "    after boot: sudo modprobe gpio-mockup gpio_mockup_ranges=-1,32,-1,32,-1,32"
  echo "    sample C: $ROOT/examples/guest-blink.c"
  exec qemu-system-arm \
    -M virt \
    -cpu cortex-a15 \
    -m "$MEM" \
    -smp 2 \
    -nographic \
    -drive if=virtio,file="$DISK",format=qcow2 \
    -drive if=virtio,file="$SEED",format=raw \
    -netdev user,id=net0,hostfwd=tcp::"${SSH_PORT}"-:22 \
    -device virtio-net-device,netdev=net0
}

cmd_ssh() {
  need ssh
  exec ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null debian@127.0.0.1
}

case "${1:-run}" in
  fetch) cmd_fetch ;;
  seed) cmd_seed ;;
  run) cmd_fetch; cmd_run ;;
  ssh) cmd_ssh ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
