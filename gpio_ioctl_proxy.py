#!/usr/bin/env python3
"""Native host helper: perform GPIO chipinfo ioctl for a qemu-user guest.

Run this on the RHEL9 *host* (64-bit). Point a preload/proxy at it instead of
issuing GPIO ioctls through broken qemu-user.

Example:
  python3 tools/gpio_ioctl_proxy.py /dev/gpiochip0
"""
from __future__ import annotations

import argparse
import ctypes
import fcntl
import os
import sys

GPIO_MAX_NAME_SIZE = 32
# Host x86_64 chipinfo (size 72 → 0x8048B401)
GPIO_GET_CHIPINFO_IOCTL = 0x8048B401


class GpiochipInfo(ctypes.Structure):
    _fields_ = [
        ("name", ctypes.c_char * GPIO_MAX_NAME_SIZE),
        ("label", ctypes.c_char * GPIO_MAX_NAME_SIZE),
        ("lines", ctypes.c_uint32),
        ("_pad", ctypes.c_uint32),
    ]


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("device", nargs="?", default="/dev/gpiochip0")
    args = p.parse_args()

    fd = os.open(args.device, os.O_RDONLY | os.O_CLOEXEC)
    try:
        info = GpiochipInfo()
        fcntl.ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, info)
        print(
            f"host chipinfo ok: name={info.name.decode()!r} "
            f"label={info.label.decode()!r} lines={info.lines}"
        )
        print(
            "If this works natively but fails in the 32-bit binfmt container, "
            "the bug is qemu-user cmd sign-extend / size bits — "
            "see docs/host-ioctl-signextend-fix.md"
        )
        return 0
    except OSError as e:
        print(f"host ioctl failed: {e}", file=sys.stderr)
        return 1
    finally:
        os.close(fd)


if __name__ == "__main__":
    sys.exit(main())
