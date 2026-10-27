#!/usr/bin/env python3
"""Probe a GPIO character device (chipinfo ioctl).

Reports open/ioctl errno clearly so container vs host failures are obvious.
Does not require the gpiod Python bindings.
"""
from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import os
import sys

# uapi/linux/gpio.h
GPIO_MAX_NAME_SIZE = 32

# _IOR(0xB4, 0x01, struct gpiochip_info) — size 72 (68 + pad) on Linux
GPIO_GET_CHIPINFO_IOCTL = 0x8048B401


class GpiochipInfo(ctypes.Structure):
    _fields_ = [
        ("name", ctypes.c_char * GPIO_MAX_NAME_SIZE),
        ("label", ctypes.c_char * GPIO_MAX_NAME_SIZE),
        ("lines", ctypes.c_uint32),
        ("_pad", ctypes.c_uint32),
    ]


def probe(path: str) -> int:
    print(f"open {path}", flush=True)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
    except OSError as e:
        name = errno.errorcode.get(e.errno, "UNKNOWN")
        print(f"open failed: errno={e.errno} ({name}) {e.strerror}", file=sys.stderr)
        if e.errno == errno.ENOENT:
            print("  hint: device node missing in this mount namespace", file=sys.stderr)
        elif e.errno in (errno.EACCES, errno.EPERM):
            print("  hint: permissions or SELinux (RHEL: label=disable for dev)", file=sys.stderr)
        return 1

    try:
        chip = GpiochipInfo()
        try:
            fcntl.ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, chip)
        except OSError as e:
            name = errno.errorcode.get(e.errno, "UNKNOWN")
            print(
                f"ioctl(GPIO_GET_CHIPINFO_IOCTL) failed: "
                f"errno={e.errno} ({name}) {e.strerror}",
                file=sys.stderr,
            )
            hints = {
                errno.ENODEV: "chip gone / stale node / not the real gpiochip",
                errno.ENOTTY: "not a gpio chip, or ABI mismatch (qemu-user 32-bit?)",
                errno.EINVAL: "ABI mismatch or bad ioctl size (arch mismatch?)",
            }
            if e.errno in hints:
                print(f"  hint: {hints[e.errno]}", file=sys.stderr)
            return 2

        label = chip.label.decode("utf-8", "replace").rstrip("\0") or "(no label)"
        cname = chip.name.decode("utf-8", "replace").rstrip("\0")
        print(f"chip name={cname!r} label={label!r} lines={chip.lines}")
        print("probe ok")
        return 0
    finally:
        os.close(fd)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("device", nargs="?", default="/dev/gpiochip0")
    args = p.parse_args()
    return probe(args.device)


if __name__ == "__main__":
    sys.exit(main())
