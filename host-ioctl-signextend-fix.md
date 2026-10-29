# 32-bit qemu-user → host GPIO: sign-extended ioctl

## What is going wrong

Guest (32-bit) issues:

```text
ioctl(fd, 0x8044b401, &gpiochip_info)   /* size field = 68 = 0x44 */
```

Broken qemu-user promotes that cmd as a **signed** 32-bit value into a 64-bit host syscall:

```text
0x8044b401  →  0xffffffff8044b401
```

Host `gpio` chardev never matches that command → `ENOTTY` / “ioctl device” errors.  
Device node + permissions can be fine.

## Why “mask only” is not enough

| Cmd | Meaning |
| --- | --- |
| `0x8044b401` | guest / 32-bit `sizeof(gpiochip_info)` = **68** |
| `0x8048b401` | host / 64-bit `sizeof(gpiochip_info)` = **72** |

A shim that only does `cmd & 0xffffffff` still forwards **`0x8044b401`**, which the **host** gpio driver does not register. You must also **rewrite the size bits** (and for other GPIO ioctls, convert structs / map returned fds).

```text
fixed = guest_cmd & 0xffffffff;
if (is_gpio_chipinfo(fixed))
    fixed = host_GPIO_GET_CHIPINFO_IOCTL;  /* 0x8048b401 on x86_64 */
```

## Solutions that actually work

### 1) Host chardev shim (kernel module) — improved version of the slide

Fits: QEMU locked, 32-bit image locked, can load a module on RHEL 9.

1. Out-of-tree module creates `/dev/gpiochip_qemu` (or similar).
2. On `unlocked_ioctl` / `compat_ioctl`:
   - `cmd32 = cmd & 0xffffffff` (and treat the arg as the guest pointer qemu already passed through).
   - Map **guest** GPIO cmds → **host** cmds (size/nr table for every v1 ioctl you need).
   - For chipinfo: copy user buffer, call host gpiochip via `vfs_ioctl` / opened filp with **host** cmd, copy back (layout is mostly identical for `gpiochip_info`; still verify).
   - For `GPIO_GET_LINEHANDLE` / `LINEEVENT`: convert request struct, run host ioctl, return fd (careful with 32-bit vs 64-bit `gpiohandle_request` padding).
3. Pass `/dev/gpiochip_qemu` into the container instead of the real chip.

Without step “map to host ioctl number + struct”, the slide’s shim will still fail after un-sign-extending.

RHEL note: needs `kernel-devel`, signed/allowed modules (Secure Boot / `mokutil`), and usually an unsupported out-of-tree policy conversation.

### 2) Userspace proxy (no custom kernel module)

Fits: cannot load modules; can run a helper on the host.

```text
32-bit app  --(unix socket / LD_PRELOAD)--  native x86_64 helper
                                              └── real ioctl(/dev/gpiochip0)
```

- Helper is host-arch, talks to real chips correctly.
- Guest never issues GPIO ioctls through qemu-user (or `LD_PRELOAD` intercepts `ioctl`/`open` on `gpiochip*` and redirects to the socket).

This is the most practical “locks” escape if kmods are forbidden. Not “impossible.”

### 3) CUSE device on the host

FUSE **CUSE** userspace chardev implements the same fix as (1) without your own `.ko` (still needs `fuse` / cuse). Same cmd remap rules.

### 4) Leave qemu-user entirely (best for “emulate board + run C”)

```text
qemu-system-arm -M virt + Debian armhf
  └── gpio-mockup inside the guest
```

Guest kernel sees native 32-bit ioctls. No sign-extend, no shim.  
See [emulate-beaglebone.md](emulate-beaglebone.md) and `./scripts/run-bbb-virt.sh`.

### 5) Patch QEMU (if the lock softens)

Proper linux-user GPIO thunks + truncate cmd to 32-bit before host `ioctl`.  
Scaffolds: [qemu-linux-user-gpio-thunks.md](qemu-linux-user-gpio-thunks.md).

## What does **not** fix it

| Idea | Why |
| --- | --- |
| Mask-only shim | Guest size 68 ≠ host size 72 |
| “Permissions / --device” | Already past `open()` |
| Matching libgpiod 1.6.3 alone | Still goes through broken qemu cmd path |
| Sysfs GPIO | Different API; still may hit other emulation gaps |

## Minimal chipinfo remap table (x86_64 host)

| Guest (armhf) cmd | Host cmd | Ioctl |
| --- | --- | --- |
| `0x8044b401` | `0x8048b401` | `GPIO_GET_CHIPINFO` |
| (derive similarly) | (from host `linux/gpio.h`) | lineinfo / handle / … |

Always generate host numbers from the **host** kernel headers (`#include <linux/gpio.h>` in the shim), don’t hard-code forever without checking `sizeof`.

## Bottom line

- The slide’s **direction** (fix at the host receiver) is valid under your locks.
- Implement **un-sign-extend + guest→host ioctl/struct translation**, not mask alone.
- If you **cannot** load a module, use a **userspace proxy** or **qemu-system virt** — the problem is not “technically impossible.”
