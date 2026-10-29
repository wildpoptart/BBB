#!/usr/bin/env python3
"""Drive a line via libgpiod 1.x CLI (gpioset/gpioget)."""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys


def need(cmd: str) -> str:
    path = shutil.which(cmd)
    if not path:
        raise SystemExit(
            f"missing {cmd!r}. Install libgpiod-utils 1.6.x, or use:\n"
            f"  python3 tools/gpiod_usermock.py --demo"
        )
    return path


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--chip", default="gpiochip0")
    p.add_argument("--line", default="0", help="numeric offset (1.x CLI)")
    p.add_argument("--value", type=int, choices=(0, 1), default=1)
    args = p.parse_args()

    gpioset = need("gpioset")
    gpioget = need("gpioget")

    # libgpiod 1.x
    subprocess.check_call([gpioset, args.chip, f"{args.line}={args.value}"])
    out = subprocess.check_output([gpioget, args.chip, args.line], text=True).strip()
    print(f"{args.chip} {args.line} -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
