# RHEL 9 GPIO lab on Zorin — libgpiod 1.6.3, no gpio-sim

## Host prep

```bash
sudo apt update
sudo apt install -y docker.io "linux-modules-extra-$(uname -r)"
modinfo gpio-mockup    # required for /dev/gpiochip* path
sudo usermod -aG docker "$USER" && newgrp docker
```

## Run

```bash
./scripts/run-rhel9-on-zorin.sh build
./scripts/run-rhel9-on-zorin.sh run
```

Entrypoint loads **gpio-mockup** (never gpio-sim) and drops you into a shell with libgpiod **1.6.3**.

## libgpiod 1.x vs 2.x CLI

| Task | 1.6.3 (this kit) | 2.x (not used) |
| --- | --- | --- |
| Set line | `gpioset gpiochip0 0=1` | `gpioset -c gpiochip0 -t 0 0=1` |
| Get line | `gpioget gpiochip0 0` | `gpioget -c gpiochip0 0` |

## If gpio-mockup is unavailable

```bash
./scripts/run-rhel9-on-zorin.sh usermock
python3 tools/gpiod_usermock.py --demo
```

Usermock does **not** create `/dev/gpiochip*`; stock `gpiodetect` will stay empty. Use it to exercise app logic that imports the mock API.

## Privileges

| Flag | Why |
| --- | --- |
| `--privileged` | `modprobe gpio-mockup`, access `/dev` |
| `-v /lib/modules:/lib/modules:ro` | Load **Zorin’s** `gpio-mockup.ko` from inside UBI |
| `-v /dev:/dev` | See new gpiochip nodes |
