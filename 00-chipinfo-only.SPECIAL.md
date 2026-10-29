# Fix failing `GPIO_GET_CHIPINFO` first (minimal, reliable)

If chipinfo fails under qemu-user, do **not** trust automatic `STRUCT(gpiochip_info)` sizing yet. Use a hard guest cmd + `IOCTL_SPECIAL`.

## Why chipinfo fails

| Side | `gpiochip_info` size | ioctl cmd |
| --- | --- | --- |
| 32-bit guest (armhf) | **68** | `0x8044b401` |
| 64-bit host (x86_64) | **72** | `0x8048b401` |

QEMU matches **`target_cmd == cmd` exactly**. If your `TARGET_GPIO_GET_CHIPINFO_IOCTL` was built with size 72, the guest’s `0x8044b401` never matches → `Unsupported ioctl` / chipinfo fails.

## Drop-in fix (chipinfo only)

### 1) `linux-user/syscall_defs.h`

```c
/* Packed as on 32-bit: 32 + 32 + 4 = 68, no trailing pad */
struct target_gpiochip_info {
    char name[32];
    char label[32];
    abi_uint lines;
};
QEMU_BUILD_BUG_ON(sizeof(struct target_gpiochip_info) != 68);

/* Hard number for armhf/i386 guests — do NOT use sizeof(host struct) */
#define TARGET_GPIO_GET_CHIPINFO_IOCTL 0x8044b401
```

If your guest is **not** little-endian 32-bit with size 68, decode the failing cmd from `QEMU_LOG=unimp` and put **that** value in the `#define`.

### 2) `linux-user/syscall.c` — handler (before ioctl table)

```c
#include <linux/gpio.h>

static abi_long do_ioctl_gpio_chipinfo(const IOCTLEntry *ie, uint8_t *buf_temp,
                                       int fd, int cmd, abi_long arg)
{
    struct target_gpiochip_info *target;
    struct gpiochip_info host;
    abi_long ret;

    target = lock_user(VERIFY_WRITE, arg, sizeof(*target), 0);
    if (!target) {
        return -TARGET_EFAULT;
    }

    memset(&host, 0, sizeof(host));
    ret = get_errno(safe_ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &host));
    if (is_error(ret)) {
        unlock_user(target, arg, 0);
        return ret;
    }

    memcpy(target->name, host.name, sizeof(target->name));
    memcpy(target->label, host.label, sizeof(target->label));
    __put_user(host.lines, &target->lines);
    unlock_user(target, arg, sizeof(*target));
    return ret;
}
```

### 3) `linux-user/ioctls.h`

```c
IOCTL_SPECIAL(GPIO_GET_CHIPINFO_IOCTL, IOC_R,
              do_ioctl_gpio_chipinfo, MK_PTR(TYPE_PTRVOID))
```

`IOCTL_SPECIAL(GPIO_GET_CHIPINFO_IOCTL, …)` expands so:

- `target_cmd` = `TARGET_GPIO_GET_CHIPINFO_IOCTL` → **`0x8044b401`**
- `host_cmd` = `GPIO_GET_CHIPINFO_IOCTL` → host **`0x8048b401`** (from `<linux/gpio.h>`)

You never pass the guest cmd to the host kernel.

### 4) Rebuild and install the binary binfmt actually runs

```bash
make -j"$(nproc)" qemu-arm  # or arm-linux-user / qemu-arm-static
# replace the file inside your binfmt Docker image / /usr/bin/qemu-arm-static
QEMU_LOG=unimp gpiodetect
```

**Success:** no `Unsupported ioctl` for `0x8044b401`; chip name/lines print.  
**Still failing:** paste the exact `QEMU_LOG` line (full `cmd=…`).

## Verify sizeof at build time

If `QEMU_BUILD_BUG_ON(… != 68)` fires, your `abi_uint` / packing is wrong for that target — fix the struct until it is 68, or set `TARGET_GPIO_GET_CHIPINFO_IOCTL` to the cmd from the log (must still copy only 68 bytes to the guest).

## After chipinfo works

Add lineinfo / linehandle using [qemu-linux-user-gpio-thunks.md](../../docs/qemu-linux-user-gpio-thunks.md). Do not move on until `gpiodetect` works.
