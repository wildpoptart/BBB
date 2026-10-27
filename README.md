# Emulate BeagleBone Black GPIO on RHEL 9

You do **not** need a BeagleBone. This toolkit creates **real** `/dev/gpiochip*` character devices on your RHEL 9 machine (via the kernel `gpio-sim` module) that look BBB-like, then lets you write libgpiod **2.2.1** code against them — in a container or on the host.

```text
RHEL 9 kernel
  gpio-sim  →  /dev/gpiochip0..2   (BBB-style banks + P8_/P9_ line names)
       ↑
  your app / Debian container (libgpiod 2.2.1)
```

That is still “host GPIO”: the chardevs live in the RHEL kernel. They are just simulated by the kernel instead of an AM335x SoC.

## Quick start

```bash
# 1) Create BBB-like chips on RHEL 9 (once per boot, needs root)
sudo ./scripts/setup-gpio-sim.sh

# 2) Confirm chips + ioctl work on the host
./scripts/diagnose-gpio.sh

# 3) Optional: Debian container with the same libgpiod 2.2.1 as BBB images
./scripts/run-bbb-container.sh build
./scripts/run-bbb-container.sh run
```

Host after setup:

```text
/dev/gpiochip0   label gpio-0-31    lines named P8_*
/dev/gpiochip1   label gpio-32-63   lines named P9_*
/dev/gpiochip2   label gpio-64-95
```

## Write code against it

Same APIs as on a real board:

```bash
gpiodetect
gpioinfo gpiochip0
gpioset -c gpiochip0 P8_3=1          # libgpiod 2.x CLI
gpioget -c gpiochip0 P8_3
```

Or from C/Python with libgpiod 2.2.1 — open `/dev/gpiochip0`, request lines by name or offset.

Probe without the CLI:

```bash
python3 tools/gpio_probe.py /dev/gpiochip0
```

## Container on RHEL 9

If you hit `ioctl` / “No such device” **inside** the container while the host chips work, the devices were not passed through (or SELinux blocked them):

```bash
./scripts/run-bbb-container.sh run
# expands to --device=/dev/gpiochipN … --security-opt label=disable
```

See [docs/ioctl-container.md](docs/ioctl-container.md).

## What you get

| Piece | Purpose |
| --- | --- |
| `scripts/setup-gpio-sim.sh` | Load `gpio-sim` (or `gpio-mockup`) and create BBB-like chips |
| `scripts/diagnose-gpio.sh` | Verify host chips + ioctl + SELinux hints |
| `scripts/run-bbb-container.sh` | Debian + libgpiod 2.2.1 with host chip passthrough |
| `tools/gpio_probe.py` | Minimal chipinfo ioctl probe |
| `examples/smoke-test.sh` | End-to-end: detect → set → get on the sim chips |

## Requirements (RHEL 9)

- Root for `modprobe` / configfs setup
- Kernel module **`gpio-sim`** (preferred) or **`gpio-mockup`** on older 9.x kernels
- Podman or Docker only if you want the Debian/libgpiod container
- Optional: `libgpiod-utils` on the host for `gpiodetect` / `gpioinfo`

```bash
# module present?
modinfo gpio-sim || modinfo gpio-mockup
```

## Limits vs a real BBB

| Emulated | Not emulated |
| --- | --- |
| `/dev/gpiochip*`, libgpiod v2 ioctls | Pinmux / cape overlays / `/boot/uEnv.txt` |
| Line request, set, get, edges (if sim supports) | PRU, ADC (AIN), PWM hardware |
| P8_/P9_-style **names** for app lookups | Exact AM335x bank/offset → header pin map |

Good enough to develop and test **GPIO application logic** before deploying the same libgpiod code to a real Debian BBB image.

## License

MIT
