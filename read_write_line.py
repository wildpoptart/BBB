#!/usr/bin/env python3
"""Minimal example: drive a BBB-emulated line via the libgpiod v2 CLI.

Uses gpioset/gpioget from libgpiod 2.x (host tools or the project container).
For a pure-C API example, build against libgpiod 2.2.1 on the board image.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys


def need(cmd: str) -> str:
    path = shutil.which(cmd)
    if not path:
        raise SystemExit(
            f"missing {cmd!r}. Install libgpiod-utils, or run inside:\n"
            f"  ./scripts/run-bbb-container.sh shell"
        )
    return path


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--chip", default="gpiochip0")
    p.add_argument("--line", default="P8_3", help="line name or offset")
    p.add_argument("--value", type=int, choices=(0, 1), default=1)
    args = p.parse_args()

    gpioset = need("gpioset")
    gpioget = need("gpioget")

    # libgpiod 2.x: gpioset -c <chip> -t 0 <line>=<val>
    subprocess.check_call(
        [gpioset, "-c", args.chip, "-t", "0", f"{args.line}={args.value}"],
    )
    out = subprocess.check_output(
        [gpioget, "-c", args.chip, args.line],
        text=True,
    ).strip()
    print(f"{args.chip} {args.line} -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
