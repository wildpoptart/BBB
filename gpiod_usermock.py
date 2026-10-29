#!/usr/bin/env python3
"""Userspace BeagleBone-like GPIO mock for libgpiod *logic* testing.

Use this when you cannot load gpio-sim / gpio-mockup. It does **not** create
/dev/gpiochip* and does **not** speak the kernel ioctl ABI — so stock
gpiodetect/gpioset will not see it. Your app (or tests) import this module
instead of talking to hardware.

API shape mirrors common libgpiod 1.6 patterns: chips → lines → get/set.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field


@dataclass
class Line:
    offset: int
    name: str
    value: int = 0
    direction: str = "input"  # input | output


@dataclass
class Chip:
    name: str
    label: str
    lines: list[Line] = field(default_factory=list)

    def line(self, key: int | str) -> Line:
        if isinstance(key, int):
            return self.lines[key]
        for ln in self.lines:
            if ln.name == key:
                return ln
        raise KeyError(f"line not found: {key!r}")

    def set(self, key: int | str, value: int) -> None:
        ln = self.line(key)
        ln.direction = "output"
        ln.value = 1 if value else 0

    def get(self, key: int | str) -> int:
        return self.line(key).value


def make_bbb_board(lines_per_bank: int = 32) -> list[Chip]:
    """Three banks; bank0/1 use P8_/P9_ style names for look-ups."""
    chips: list[Chip] = []

    def bank(name: str, label: str, prefix: str | None) -> Chip:
        lines = []
        for i in range(lines_per_bank):
            if prefix == "P8":
                lname = f"P8_{i + 1}"
            elif prefix == "P9":
                lname = f"P9_{i + 1}"
            else:
                lname = f"{label}_{i}"
            lines.append(Line(offset=i, name=lname))
        return Chip(name=name, label=label, lines=lines)

    chips.append(bank("gpiochip0", "gpio-0-31", "P8"))
    chips.append(bank("gpiochip1", "gpio-32-63", "P9"))
    chips.append(bank("gpiochip2", "gpio-64-95", None))
    return chips


def demo() -> int:
    chips = make_bbb_board()
    print("usermock chips (no /dev/gpiochip — in-process only):")
    for c in chips:
        print(f"  {c.name}  label={c.label!r}  lines={len(c.lines)}")

    c0 = chips[0]
    c0.set("P8_3", 1)
    print(f"set {c0.name} P8_3=1 → get={c0.get('P8_3')}")
    c0.set(0, 0)
    print(f"set {c0.name} offset0=0 → get={c0.get(0)}")
    print("usermock demo ok")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--demo", action="store_true", help="run a small set/get demo")
    args = p.parse_args()
    if args.demo:
        return demo()
    p.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
