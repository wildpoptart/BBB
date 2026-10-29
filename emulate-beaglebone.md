# Goal: emulate a BeagleBone and run C on it

You want a **simulated board** where you can build and run **C** (and talk to GPIO with libgpiod 1.6.x), without owning a BBB.

## Reality check

| Approach | Runs your C? | Feels like BBB? | GPIO |
| --- | --- | --- | --- |
| **A. `qemu-system-arm -M virt` + Debian armhf** (recommended) | Yes | Same CPU class + Debian userspace | `gpio-mockup` **inside** the guest |
| **B. qemu-linaro `-M beagle`** (Beagle *Board*, not Bone) | Yes, with work | Closer boot/DT story; still not AM335x BBB | Board model limited |
| **C. binfmt qemu-user 32-bit container on RHEL9** | Yes for userspace | Not a board — host kernel | Broken unless you patch QEMU ioctls |
| **D. Host gpio-mockup + native container** | C on host/container | No board OS | Host chips only |

**Stock QEMU has no BeagleBone Black (`am335x`) machine.** Do not expect an official BBB SD image to boot under upstream `qemu-system-arm`.

For “write C, run it on a 32-bit ARM Debian like the board,” use **path A**.

```text
Your PC (Zorin / RHEL9)
  └── qemu-system-arm -M virt -cpu cortex-a15   # full system, not binfmt
        └── Debian armhf guest
              ├── gcc / your .c → binary
              ├── libgpiod 1.6.x
              └── gpio-mockup → /dev/gpiochip*  (guest kernel)
```

No qemu-user ioctl thunks. Guest libgpiod talks to the **guest** kernel.

## Path A — recommended (stock QEMU)

### 1) Host packages

```bash
# Debian/Ubuntu/Zorin
sudo apt install qemu-system-arm qemu-utils cloud-image-utils wget

# RHEL9 (enable CRB/EPEL as needed)
sudo dnf install qemu-system-arm qemu-img wget
```

### 2) Get a 32-bit ARM Debian cloud image

```bash
mkdir -p ~/bbb-virt && cd ~/bbb-virt
# Debian armhf generic cloud image (bookworm example — check current URL on cloud.debian.org)
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-armhf.qcow2
qemu-img resize debian-12-generic-armhf.qcow2 8G
```

### 3) Boot the guest

Use the helper in this repo:

```bash
./scripts/run-bbb-virt.sh
```

Or manually (shape of the command):

```bash
qemu-system-arm \
  -M virt \
  -cpu cortex-a15 \
  -m 1G \
  -smp 2 \
  -nographic \
  -drive if=virtio,file=debian-12-generic-armhf.qcow2,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-device,netdev=net0
```

(Cloud images need a seed ISO / cloud-init for login; the helper builds one.)

### 4) Inside the guest — C + GPIO

```bash
sudo apt update
sudo apt install -y build-essential libgpiod-dev gpiod

# Fake BBB-like chips in the *guest* kernel
sudo modprobe gpio-mockup gpio_mockup_ranges=-1,32,-1,32,-1,32
gpiodetect

# Your program
cat > blink.c <<'EOF'
#include <gpiod.h>
#include <stdio.h>
#include <unistd.h>
int main(void) {
    struct gpiod_chip *chip = gpiod_chip_open_by_name("gpiochip0");
    if (!chip) { perror("open"); return 1; }
    struct gpiod_line *line = gpiod_chip_get_line(chip, 0);
    gpiod_line_request_output(line, "blink", 0);
    for (int i = 0; i < 5; i++) {
        gpiod_line_set_value(line, 1); sleep(1);
        gpiod_line_set_value(line, 0); sleep(1);
    }
    gpiod_chip_close(chip);
    return 0;
}
EOF
gcc blink.c -lgpiod -o blink
./blink
```

That is **libgpiod 1.x** API (matches 1.6.3-style). Adjust package versions with `gpiodetect --version`.

### 5) Cross-compile from the host (optional)

```bash
sudo apt install gcc-arm-linux-gnueabihf
arm-linux-gnueabihf-gcc blink.c -lgpiod -o blink   # need armhf libgpiod in sysroot
scp -P 2222 blink user@localhost:
```

Often easier: compile **inside** the guest.

## Path B — closer “Beagle” machine (harder)

Upstream QEMU ≠ BeagleBone Black. Old **qemu-linaro** had `-M beagle` / `beaglexm` (OMAP3 Beagle *Board*). People reuse that with an OMAP3 kernel/DTB and a Debian rootfs. It is fragile, not AM335x, and not what you want for day-to-day C work.

Only pursue this if you specifically need that machine model.

## What to avoid for this goal

- **binfmt + Docker armhf + host `/dev/gpiochip*`** — qemu-user missing GPIO ioctls (your current pain).
- Expecting a **BeagleBoard.org BBB `.img`** to boot on stock `-M virt` without replacing kernel/boot.
- Patching QEMU linux-user **unless** you must keep the binfmt container approach.

## How this repo fits

| Piece | Role for “emulate board + run C” |
| --- | --- |
| `scripts/run-bbb-virt.sh` | Boot Debian armhf under `qemu-system-arm -M virt` |
| `examples/guest-blink.c` | Minimal libgpiod 1.x C sample for the guest |
| `scripts/setup-gpio-mockup.sh` | Same idea on a **bare-metal** RHEL host (not a board emu) |
| QEMU linux-user patches | Only if you stay on binfmt; **not** needed for path A |

## Summary

1. Use **full system** QEMU (`qemu-system-arm`), not binfmt qemu-user.  
2. Machine **`virt` + Debian armhf** = practical “BBB userspace” lab for C.  
3. Load **gpio-mockup in the guest** for `/dev/gpiochip*`.  
4. Compile and run C **in the guest** (or cross-compile to armhf).
