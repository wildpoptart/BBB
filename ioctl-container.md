# ioctl / missing gpiochip (RHEL 9 BBB emulation)

## Goal

Emulate BeagleBone GPIO on RHEL 9 with **kernel `gpio-sim`**, then use those host `/dev/gpiochip*` nodes from your app or container (libgpiod 2.2.1).

```bash
sudo ./scripts/setup-gpio-sim.sh   # creates host chips
./scripts/diagnose-gpio.sh         # must succeed on host first
```

## Symptom inside a container

```text
gpiodetect: No such device
ioctl(...): No such device
```

while on the host `ls /dev/gpiochip*` and `gpiodetect` work.

## Decision tree

```
Host: ls /dev/gpiochip*
        │
        ├─ empty ──► sudo ./scripts/setup-gpio-sim.sh
        │              (modprobe gpio-sim / gpio-mockup)
        │
        └─ chips present (this is your “BBB” GPIO)
                 │
                 Container: ls /dev/gpiochip*
                        │
                        ├─ empty ──► pass them in:
                        │              --device=/dev/gpiochip0 …
                        │              ./scripts/run-bbb-container.sh run
                        │
                        └─ node exists
                                 ├─ EACCES → permissions / SELinux
                                 │            --security-opt label=disable
                                 ├─ ENOTTY/EINVAL → arch/ABI (avoid qemu-user)
                                 └─ ENODEV → stale node; re-run setup + recreate container
```

## RHEL 9 Podman

```bash
sudo ./scripts/setup-gpio-sim.sh

podman run --rm -it \
  --device=/dev/gpiochip0 \
  --device=/dev/gpiochip1 \
  --device=/dev/gpiochip2 \
  --security-opt label=disable \
  localhost/bbb-gpio:libgpiod-2.2.1 \
  gpiodetect
```

## Why libgpiod 2.2.1 alone is not enough

Matching the BBB’s libgpiod version keeps your **API** aligned. The container still needs the host chardev nodes (`--device=...`) created by `setup-gpio-sim.sh` on RHEL 9.
