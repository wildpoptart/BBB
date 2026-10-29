#!/usr/bin/env python3
"""Decode a GPIO ioctl command word (guest or host)."""
from __future__ import annotations

import argparse
import sys

DIRS = {0: "NONE", 1: "WRITE", 2: "READ", 3: "RW"}


def decode(cmd: int) -> None:
    cmd &= 0xFFFFFFFF
    size = (cmd >> 16) & 0x3FFF
    typ = (cmd >> 8) & 0xFF
    nr = cmd & 0xFF
    direction = (cmd >> 30) & 0x3
    print(f"cmd        0x{cmd:08x}")
    print(f"dir        {direction} ({DIRS.get(direction, '?')})")
    print(f"type       0x{typ:02x}")
    print(f"nr         0x{nr:02x}")
    print(f"size       {size}")
    if typ == 0xB4 and nr == 0x01:
        if size == 68:
            print("hint       guest/32-bit style GPIO_GET_CHIPINFO (expect TARGET match)")
        elif size == 72:
            print("hint       host/64-bit style GPIO_GET_CHIPINFO (host_cmd)")
        else:
            print("hint       chipinfo nr, unusual size — check struct packing")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "cmd",
        help="ioctl cmd (e.g. 0x8044b401 or 0xffffffff8044b401)",
    )
    args = p.parse_args()
    try:
        cmd = int(args.cmd, 0)
    except ValueError:
        print("invalid cmd", file=sys.stderr)
        return 1
    if cmd > 0xFFFFFFFF:
        print(f"truncated to 32-bit: 0x{cmd & 0xFFFFFFFF:08x} (was 0x{cmd:x})")
    decode(cmd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
