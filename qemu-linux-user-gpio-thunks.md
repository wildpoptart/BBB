# Adding GPIO ioctl thunks to QEMU linux-user (for libgpiod 1.6.3)

You are patching **qemu-user** so a 32-bit guest can `ioctl()` host `/dev/gpiochip*`. Stock QEMU has **zero** `GPIO_*` entries — you must add them, then rebuild the binfmt/`qemu-*-static` you use in Docker.

## Files to touch (QEMU tree)

| File | What to add |
| --- | --- |
| `linux-user/syscall_defs.h` | `target_` structs + `TARGET_GPIO_*` ioctl numbers |
| `linux-user/syscall_types.h` | `STRUCT(gpio…)` marshalling layouts |
| `linux-user/ioctls.h` | `IOCTL(...)` / `IOCTL_SPECIAL(...)` rows |
| `linux-user/syscall.c` | `do_ioctl_gpio_*` for fd-returning calls |
| (optional) `linux-user/strace.list` | names for `QEMU_STRACE` |

Rebuild at least the user targets you need (`arm-linux-user`, `arm-linux-user-static`, etc.) and refresh the binfmt image that embeds that QEMU (~10.x).

## Phase order (libgpiod 1.6.3 / uAPI v1)

Do **phase 1 first** — that unblocks `gpiodetect` / chipinfo. Then phase 2 for get/set. Then phase 3 for request/event fds.

### Phase 1 — chip / line info (plain `IOCTL`)

| Ioctl | Direction | Struct |
| --- | --- | --- |
| `GPIO_GET_CHIPINFO_IOCTL` | R | `gpiochip_info` |
| `GPIO_GET_LINEINFO_IOCTL` | RW | `gpioline_info` |
| `GPIO_GET_LINEINFO_WATCH_IOCTL` | RW | `gpioline_info` (if you need watch) |
| `GPIO_GET_LINEINFO_UNWATCH_IOCTL` | RW | `__u32` |

These have **no pointers and no fds**. Automatic thunking is enough.

### Phase 2 — values / config on an existing handle fd

| Ioctl | Struct |
| --- | --- |
| `GPIOHANDLE_GET_LINE_VALUES_IOCTL` | `gpiohandle_data` |
| `GPIOHANDLE_SET_LINE_VALUES_IOCTL` | `gpiohandle_data` |
| `GPIOHANDLE_SET_CONFIG_IOCTL` | `gpiohandle_config` |

Still plain `IOCTL` — but the **fd you call them on** is the handle fd from phase 3.

### Phase 3 — must be `IOCTL_SPECIAL` (returns `int fd`)

| Ioctl | Struct | Why special |
| --- | --- | --- |
| `GPIO_GET_LINEHANDLE_IOCTL` | `gpiohandle_request` | kernel writes `fd` |
| `GPIO_GET_LINEEVENT_IOCTL` | `gpioevent_request` | kernel writes `fd` |

Copy fields in/out yourself. After a successful host ioctl, put the new host fd into the guest-visible struct (linux-user usually keeps guest fd == host fd for these anonymous fds; still `tswap32`/`__put_user` the value). Do **not** use plain `IOCTL()` here — padding around `int fd` and ioctl size bits differ between 32-bit guest and 64-bit host.

## Constants

```c
#define GPIO_MAX_NAME_SIZE 32
#define GPIOHANDLES_MAX    64
#define GPIO_IOCTL_TYPE    0xB4
```

Kernel (host) numbers use `_IOR`/`_IOWR` with **host** `sizeof`. Guest numbers must use `TARGET_IOR`/`TARGET_IOWR` with **`sizeof(struct target_…)`**.

## Minimal `syscall_defs.h` sketches

```c
struct target_gpiochip_info {
    char name[GPIO_MAX_NAME_SIZE];
    char label[GPIO_MAX_NAME_SIZE];
    abi_uint lines;
};

struct target_gpioline_info {
    abi_uint line_offset;
    abi_uint flags;
    char name[GPIO_MAX_NAME_SIZE];
    char consumer[GPIO_MAX_NAME_SIZE];
};

struct target_gpiohandle_data {
    uint8_t values[GPIOHANDLES_MAX];
};

struct target_gpiohandle_config {
    abi_uint flags;
    uint8_t default_values[GPIOHANDLES_MAX];
    abi_uint padding[4];
};

struct target_gpiohandle_request {
    abi_uint lineoffsets[GPIOHANDLES_MAX];
    abi_uint flags;
    uint8_t default_values[GPIOHANDLES_MAX];
    char consumer_label[GPIO_MAX_NAME_SIZE];
    abi_uint lines;
    abi_int fd;          /* OUT — SPECIAL handler */
};

struct target_gpioevent_request {
    abi_uint lineoffset;
    abi_uint handleflags;
    abi_uint eventflags;
    char consumer_label[GPIO_MAX_NAME_SIZE];
    abi_int fd;          /* OUT — SPECIAL handler */
};

#define TARGET_GPIO_GET_CHIPINFO_IOCTL \
    TARGET_IOR(GPIO_IOCTL_TYPE, 0x01, struct target_gpiochip_info)
#define TARGET_GPIO_GET_LINEINFO_IOCTL \
    TARGET_IOWR(GPIO_IOCTL_TYPE, 0x02, struct target_gpioline_info)
#define TARGET_GPIO_GET_LINEHANDLE_IOCTL \
    TARGET_IOWR(GPIO_IOCTL_TYPE, 0x03, struct target_gpiohandle_request)
#define TARGET_GPIO_GET_LINEEVENT_IOCTL \
    TARGET_IOWR(GPIO_IOCTL_TYPE, 0x04, struct target_gpioevent_request)
#define TARGET_GPIOHANDLE_GET_LINE_VALUES_IOCTL \
    TARGET_IOWR(GPIO_IOCTL_TYPE, 0x08, struct target_gpiohandle_data)
#define TARGET_GPIOHANDLE_SET_LINE_VALUES_IOCTL \
    TARGET_IOWR(GPIO_IOCTL_TYPE, 0x09, struct target_gpiohandle_data)
#define TARGET_GPIOHANDLE_SET_CONFIG_IOCTL \
    TARGET_IOWR(GPIO_IOCTL_TYPE, 0x0A, struct target_gpiohandle_config)
#define TARGET_GPIO_GET_LINEINFO_UNWATCH_IOCTL \
    TARGET_IOWR(GPIO_IOCTL_TYPE, 0x0C, abi_uint)
```

Match member order/packing to the **guest** `linux/gpio.h` (32-bit Debian), not to x86_64 host layout. Use `abi_uint` / `abi_int` so thunking hits the right sizes.

## `syscall_types.h`

```c
STRUCT(gpiochip_info,
       MK_ARRAY(TYPE_CHAR, GPIO_MAX_NAME_SIZE), /* name */
       MK_ARRAY(TYPE_CHAR, GPIO_MAX_NAME_SIZE), /* label */
       TYPE_INT)                                /* lines */

STRUCT(gpioline_info,
       TYPE_INT, TYPE_INT,
       MK_ARRAY(TYPE_CHAR, GPIO_MAX_NAME_SIZE),
       MK_ARRAY(TYPE_CHAR, GPIO_MAX_NAME_SIZE))

STRUCT(gpiohandle_data,
       MK_ARRAY(TYPE_CHAR, GPIOHANDLES_MAX))

STRUCT(gpiohandle_config,
       TYPE_INT,
       MK_ARRAY(TYPE_CHAR, GPIOHANDLES_MAX),
       MK_ARRAY(TYPE_INT, 4))
```

(Omit `gpiohandle_request` / `gpioevent_request` from auto `STRUCT` if you only implement them via `IOCTL_SPECIAL`.)

## `ioctls.h`

```c
#ifdef HAVE_LINUX_GPIO_H   /* or always, if you include linux/gpio.h in syscall.c */
IOCTL(GPIO_GET_CHIPINFO_IOCTL, IOC_R,
      MK_PTR(MK_STRUCT(STRUCT_gpiochip_info)))
IOCTL(GPIO_GET_LINEINFO_IOCTL, IOC_RW,
      MK_PTR(MK_STRUCT(STRUCT_gpioline_info)))
IOCTL(GPIOHANDLE_GET_LINE_VALUES_IOCTL, IOC_RW,
      MK_PTR(MK_STRUCT(STRUCT_gpiohandle_data)))
IOCTL(GPIOHANDLE_SET_LINE_VALUES_IOCTL, IOC_RW,
      MK_PTR(MK_STRUCT(STRUCT_gpiohandle_data)))
IOCTL(GPIOHANDLE_SET_CONFIG_IOCTL, IOC_RW,
      MK_PTR(MK_STRUCT(STRUCT_gpiohandle_config)))
IOCTL(GPIO_GET_LINEINFO_UNWATCH_IOCTL, IOC_RW, MK_PTR(TYPE_INT))

IOCTL_SPECIAL(GPIO_GET_LINEHANDLE_IOCTL, IOC_RW,
              do_ioctl_gpio_linehandle, MK_PTR(TYPE_PTRVOID))
IOCTL_SPECIAL(GPIO_GET_LINEEVENT_IOCTL, IOC_RW,
              do_ioctl_gpio_lineevent, MK_PTR(TYPE_PTRVOID))
#endif
```

Host cmd symbols (`GPIO_GET_CHIPINFO_IOCTL`, …) come from **host** `<linux/gpio.h>` (build dependency: kernel headers with GPIO uAPI).

## `IOCTL_SPECIAL` outline (`syscall.c`)

```c
static abi_long do_ioctl_gpio_linehandle(const IOCTLEntry *ie, uint8_t *buf_temp,
                                         int fd, int cmd, abi_long arg)
{
    struct target_gpiohandle_request *target;
    struct gpiohandle_request host;
    abi_long ret;
    int i;

    if (!(target = lock_user(VERIFY_WRITE, arg,
                             sizeof(*target), 0))) {
        return -TARGET_EFAULT;
    }
    memset(&host, 0, sizeof(host));
    __get_user(host.flags, &target->flags);
    __get_user(host.lines, &target->lines);
    if (host.lines > GPIOHANDLES_MAX) {
        unlock_user(target, arg, 0);
        return -TARGET_EINVAL;
    }
    for (i = 0; i < host.lines; i++) {
        __get_user(host.lineoffsets[i], &target->lineoffsets[i]);
        host.default_values[i] = target->default_values[i];
    }
    memcpy(host.consumer_label, target->consumer_label,
           sizeof(host.consumer_label));

    ret = get_errno(safe_ioctl(fd, GPIO_GET_LINEHANDLE_IOCTL, &host));
    if (is_error(ret)) {
        unlock_user(target, arg, 0);
        return ret;
    }

    /* Anonymous handle fd: expose host fd number to guest */
    __put_user(host.fd, &target->fd);
    unlock_user(target, arg, sizeof(*target));
    return ret;
}
```

Same pattern for `gpioevent_request` / `GPIO_GET_LINEEVENT_IOCTL`.

If your QEMU build uses an fd-translation layer for some fds, register the new fd the same way other “kernel returns fd in struct” paths do in your tree — identity mapping is the common linux-user default.

## Verify

```bash
# rebuild qemu-arm-static (example), install into binfmt image, then:
QEMU_LOG=unimp qemu-arm-static gpiodetect
# before patch: Unsupported ioctl 0xb4...
# after phase 1: chip list prints

gpiodetect
gpioinfo gpiochip0
gpioset gpiochip0 0=1    # needs phase 2+3
gpioget gpiochip0 0
```

Native host control:

```bash
python3 tools/gpio_probe.py /dev/gpiochip0
```

## What you do **not** need for libgpiod 1.6.3

- GPIO **uAPI v2** ioctls (`GPIO_V2_*`) — that is libgpiod **2.x**
- Recompiling the kernel
- gpio-sim (this kit uses gpio-mockup / real chips)

## Pitfalls

1. **Ioctl size in the cmd word** — `TARGET_*` must use `sizeof(target_struct)`. For chipinfo on armhf that is usually **68** (`0x8044b401`). If your target struct is accidentally **72**, QEMU never matches the guest cmd → `Unsupported ioctl` while other (built-in) ioctls still work. See [qemu-ioctl-partial-success.md](qemu-ioctl-partial-success.md).
2. **`host_cmd` must stay host-sized** — e.g. `0x8048b401` on x86_64. The thunk converts the buffer; the host ioctl number is not the guest number.
3. **`int fd` padding** — linehandle/event must be `IOCTL_SPECIAL`.
4. **binfmt image** — rebuild is useless until the container’s `qemu-*-static` is replaced.
5. **Endianness** — armhf on x86_64 is fine (both LE); still use `__get_user` / `tswap*`.

Scaffold snippets: [`qemu-patches/linux-user-gpio/`](../qemu-patches/linux-user-gpio/).
