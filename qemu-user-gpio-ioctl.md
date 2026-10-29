# 32-bit Debian under binfmt/QEMU + host `/dev/gpiochip*` ioctl failures

## Your setup

```text
RHEL 9 x86_64 host
  └── Docker + binfmt (qemu-user ~10.x)
        └── 32-bit Debian userspace (armhf/i386)
              └── open(/dev/gpiochipN) OK
              └── ioctl(GPIO_GET_CHIPINFO_IOCTL, …) FAIL
```

Device node visible, permissions fine — still broken. That is expected.

## Root cause

`binfmt_misc` + **qemu-user** (linux-user) runs the 32-bit binary by translating syscalls to the **64-bit host kernel**.

GPIO chardev ioctls (`linux/gpio.h` — `GPIO_GET_CHIPINFO_IOCTL`, line-info, line-handle, …) are **not registered** in QEMU’s `linux-user/ioctls.h` (checked through QEMU **10.0** / current master: **no `GPIO_*` entries**).

So qemu-user does not marshal the guest ioctl number/struct to the host. Typical symptoms in QEMU logs / errno:

- `Unsupported ioctl: cmd=0x…` / `ioctl type=0xb4`
- `ENOTTY`, `EINVAL`, or “Inappropriate ioctl for device”
- Chipinfo fails even though `ls -l /dev/gpiochip0` works

`open()` only needs the fd — it does not need ioctl thunks. That is why passthrough looks “correct” until the first `gpio.h` ioctl.

libgpiod **1.6.3** vs **2.x** does not fix this; both issue those ioctls.

## Do you need to recompile QEMU?

| Action | Useful? |
| --- | --- |
| Rebuild stock QEMU unchanged | **No** — still no GPIO thunks |
| Rebuild QEMU **after adding** GPIO ioctl thunks | **Yes** — required for binfmt 32-bit + host gpiochip |
| Refresh binfmt Docker image with that `qemu-*-static` | **Yes** — otherwise the container keeps the old binary |

If you are adding the calls yourself, follow **[qemu-linux-user-gpio-thunks.md](qemu-linux-user-gpio-thunks.md)** and the scaffolds in `qemu-patches/linux-user-gpio/`.

Start with **chipinfo only** (`GPIO_GET_CHIPINFO_IOCTL` plain `IOCTL`), confirm `gpiodetect` works, then add lineinfo / handle values, then `IOCTL_SPECIAL` for linehandle/lineevent (`fd` out-params).

## What works instead

### 1) Native-arch container for GPIO (recommended)

Run libgpiod against host chips in an **x86_64** (or host-native) container — no binfmt for the GPIO process:

```bash
# host chips from gpio-mockup / hardware
sudo ./scripts/setup-gpio-mockup.sh
./scripts/run-rhel9-on-zorin.sh run   # native UBI9 + libgpiod 1.6.3
```

Keep the 32-bit Debian binfmt container for **build/link** of board binaries if you need armhf artifacts; do **not** do live host-gpio ioctls there.

### 2) ioctl proxy (32-bit app → native helper)

Small **native** helper on the host (or in a native sidecar) performs GPIO ioctls; the 32-bit app talks Unix socket / gRPC. Same idea as avoiding qemu-user for netlink-heavy APIs.

### 3) Full `qemu-system` guest

Boot a 32-bit kernel in **qemu-system**; put `gpio-mockup` / virtio-gpio **inside the guest**. Guest libgpiod talks to the **guest** kernel — no linux-user ioctl translation. Heavier; correct ABI-wise.

### 4) Userspace mock (logic only)

```bash
python3 tools/gpiod_usermock.py --demo
```

No `/dev/gpiochip*`; fine for control-flow tests only.

## Quick confirmation

On the host (native):

```bash
python3 tools/gpio_probe.py /dev/gpiochip0   # should be probe ok
```

Inside the **32-bit binfmt** container (same device):

```bash
python3 -c "import fcntl,os,ctypes; ..."   # same chipinfo ioctl → fails
# or: gpiodetect / gpioget → ioctl error
# QEMU_LOG=unimp qemu-...  → unsupported ioctl 0xB4....
```

If native works and binfmt fails with the same node and mode, it is **qemu-user**, not Docker device wiring.

## Relation to this repo

This kit targets **native** RHEL9/UBI + libgpiod **1.6.3** + **gpio-mockup** (no gpio-sim). It deliberately avoids qemu-user for GPIO. See [zorin-rhel9.md](zorin-rhel9.md).
