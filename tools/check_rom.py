"""
Sanity checks for the built Atari 2600 ROM.

This project targets a **16K F6-bankswitched** cartridge:
- 4 banks * 4K each
- reset vector is stored at the end of the last bank (file offset 0x3FFC)

This script is intentionally lightweight and is meant to catch the most common
build mistakes quickly:
- wrong ROM size
- obviously-wrong reset vector
"""

import argparse
import hashlib
import struct
from pathlib import Path


def main() -> int:
    """CLI entrypoint. Exits 0 on success, raises SystemExit on failure."""
    ap = argparse.ArgumentParser(description="Sanity-check the built Atari 2600 ROM.")
    ap.add_argument("rom", type=Path, nargs="?", default=Path("build/mecha.bin"))
    args = ap.parse_args()

    rom_path: Path = args.rom
    if not rom_path.exists():
        raise SystemExit(f"ERROR: ROM file not found: {rom_path}")
    data = rom_path.read_bytes()

    print(f"ROM: {rom_path} ({len(data)} bytes)")

    if len(data) != 16 * 1024:
        raise SystemExit(f"ERROR: Expected 16384 bytes (16K F6), got {len(data)}")

    sha1 = hashlib.sha1(data).hexdigest()
    print(f"SHA1: {sha1}")

    # F6 carts contain 4 independent 4K banks. Each bank has vectors at its end.
    # Depending on the bankswitch hardware/emulator behavior, reset may start in bank 0.
    # We print all reset vectors so it's obvious what will happen on startup.
    for bank in range(4):
        off = bank * 0x1000 + 0x0FFC
        reset_lo, reset_hi = struct.unpack_from("<BB", data, off)
        reset = reset_lo | (reset_hi << 8)
        print(f"Reset vector bank{bank} @0x{off:04X}: ${reset:04X}")

        # Note: on the 6507, ROM appears mirrored into $F000-$FFFF.
        if not (0xF000 <= reset <= 0xFFFF):
            raise SystemExit(
                f"ERROR: bank{bank} reset vector doesn't look like a 6507 ROM address ($F000-$FFFF): ${reset:04X}"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

