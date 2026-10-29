# Some ioctls work, the GPIO one you added does not

Typical report:

- Built-in / “native” qemu-user ioctls **work**
- Host `gpiodetect` / native 64-bit tools **work**
- The **GPIO ioctl you registered** in QEMU does **not** go through
- Kernel module shim may be off the table

That almost always means either **(A) QEMU never selects your table entry**, or **(B) your handler runs but the host rejects the cmd/struct**.

## Step 1 — Did QEMU match your entry?

In the 32-bit container (with your patched `qemu-*-static`):

```bash
export QEMU_LOG=unimp
gpiodetect
# or your chipinfo test binary
```

| Log | Meaning |
| --- | --- |
| `Unsupported ioctl: cmd=0x……` | **No table match** — your `TARGET_*` number ≠ what the guest sent |
| No “Unsupported”, but errno `ENOTTY`/`EINVAL` | Match (or pass-through) happened; **host** rejected cmd/struct |
| Works for `GPIO_GET_CHIPINFO` only | Phase-1 OK; linehandle/event still missing or wrong `IOCTL_SPECIAL` |

### Decode the cmd the guest actually sends

```bash
python3 - <<'PY'
cmd = 0x8044b401   # paste from QEMU_LOG
print(f"cmd=0x{cmd:08x}")
print(f" dir={(cmd>>30)&3} type=0x{(cmd>>8)&0xff:x} nr=0x{cmd&0xff:x} size={(cmd>>16)&0x3fff}")
PY
```

For chipinfo on **32-bit** Debian you usually see **`size=68` → `0x8044b401`**.  
On the **64-bit host**, chipinfo is **`size=72` → `0x8048b401`**.

Your QEMU entry must use:

```text
target_cmd  = 0x8044b401   # sizeof(struct target_gpiochip_info) == 68
host_cmd    = 0x8048b401   # real <linux/gpio.h> on the build host
```

If `sizeof(struct target_gpiochip_info)` became **72** (extra padding / wrong types), then:

```text
TARGET_GPIO_GET_CHIPINFO_IOCTL → 0x8048b401
guest still sends                 0x8044b401
→ exact match fails → "Unsupported ioctl" → “our GPIO command didn’t go through”
```

**Fix:** define the target struct with `abi_uint` / no host-only padding so `sizeof` is **68** on the target ABI QEMU is built for, and confirm:

```c
QEMU_BUILD_BUG_ON(sizeof(struct target_gpiochip_info) != 68);
```

(or print it once at `syscall_init`).

## Step 2 — Confirm the `IOCTL()` row is live

Checklist:

1. Snippets in **all** of: `syscall_defs.h`, `syscall_types.h`, `ioctls.h` (and SPECIAL handlers in `syscall.c` if needed).
2. Rebuilt the same binary the container uses (`qemu-arm-static` / binfmt path).  
   `which qemu-arm-static` / `ls -l $(which qemu-arm-static)` — easy to run an old binary.
3. `IOCTL(GPIO_GET_CHIPINFO_IOCTL, …)` — the macro name must match a **host** `#define` from `<linux/gpio.h>` **and** a `TARGET_GPIO_GET_CHIPINFO_IOCTL` (QEMU’s `IOCTL()` wires both). If host headers lack GPIO uAPI, the row may not compile as you think or `host_cmd` is wrong.
4. Not stuck behind `#ifdef` that is off in your configure.

## Step 3 — “Some GPIO cmds work, some don’t”

| Guest op | Ioctl | Needs |
| --- | --- | --- |
| `gpiodetect` | `GPIO_GET_CHIPINFO` | plain `IOCTL` + size **68** target |
| `gpioinfo` | `GPIO_GET_LINEINFO` | plain `IOCTL` + correct `gpioline_info` |
| `gpioset` / `gpioget` (1.6) | `GPIO_GET_LINEHANDLE` + `GPIOHANDLE_*_VALUES` | **`IOCTL_SPECIAL`** for linehandle (fd out), then plain values |
| edge wait | `GPIO_GET_LINEEVENT` | **`IOCTL_SPECIAL`** |

If chipinfo works after your patch but set/get does not, you are not failing sign-extend anymore — you still need **phase 2/3** from [qemu-linux-user-gpio-thunks.md](qemu-linux-user-gpio-thunks.md).

## Step 4 — Kernel module not available

Skip the host shim. Options:

1. **Finish QEMU thunks** (fix target `sizeof` / SPECIAL) — best if you must keep binfmt.  
2. **Userspace proxy** — native helper does host ioctls; guest avoids GPIO ioctl through qemu ([host-ioctl-signextend-fix.md](host-ioctl-signextend-fix.md)).  
3. **`qemu-system -M virt`** — run C in a real 32-bit guest kernel ([emulate-beaglebone.md](emulate-beaglebone.md)).

## Fast isolation commands

```bash
# A) Host native (must work)
python3 tools/gpio_ioctl_proxy.py /dev/gpiochip0

# B) Under your patched qemu-user
QEMU_LOG=unimp qemu-arm-static -strace gpiodetect 2>&1 | tee /tmp/qemu-gpio.log
grep -i ioctl /tmp/qemu-gpio.log
```

- **Unsupported + cmd size 68** but you registered size 72 → fix target struct/`TARGET_*`.  
- **Supported path + ENOTTY** → `host_cmd` still guest-sized or wrong; use host `GPIO_GET_CHIPINFO_IOCTL`.  
- **Chipinfo OK, gpioset fails** → add linehandle SPECIAL + values ioctls.

## Chipinfo failing specifically

Use the hard-cmd + `IOCTL_SPECIAL` recipe (skip auto `STRUCT` sizing):

→ [`qemu-patches/linux-user-gpio/00-chipinfo-only.SPECIAL.md`](../qemu-patches/linux-user-gpio/00-chipinfo-only.SPECIAL.md)

In the 32-bit image, compile `tools/chipinfo_guest_cmd.c` and set `TARGET_GPIO_GET_CHIPINFO_IOCTL` to the printed value (expect `0x8044b401`).

## Bottom line

“Native worked, the GPIO command we added didn’t” is usually **`target_cmd` mismatch (68 vs 72)** or **binfmt still running an old QEMU**, not permissions and not “GPIO impossible.” Masking sign-extension in a kernel module does not fix a QEMU table miss; fixing `sizeof(struct target_gpiochip_info)` and rebuilding the static binary does.
