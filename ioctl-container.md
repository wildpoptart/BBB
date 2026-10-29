# Missing gpiochip / ioctl (libgpiod 1.6.3, no gpio-sim)

## Create chips

```bash
sudo ./scripts/setup-gpio-mockup.sh
./scripts/diagnose-gpio.sh
```

## Container on RHEL/Zorin lab

```bash
./scripts/run-rhel9-on-zorin.sh run
```

If `/dev/gpiochip*` is missing inside the container while mockup loaded on the host, pass `/dev` and keep `--privileged` (the Zorin launcher already does).

## libgpiod 1.6.3

```bash
gpioset gpiochip0 0=1
gpioget gpiochip0 0
```

Matching **1.6.3** does not create device nodes; **gpio-mockup** (or real hardware) does. This kit does **not** use gpio-sim.

## No kernel modules

```bash
python3 tools/gpiod_usermock.py --demo
```
