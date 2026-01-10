"""
Generate playfield lookup tables for the Atari 2600 Mecha Simulator.

Why generate tables?
- The visible kernel is cycle-critical; doing bit packing at runtime would be
  too expensive and would risk scanline overruns.
- Playfield bit ordering is non-intuitive (PF0/PF2 reversed vs PF1).
  Generating tables in Python keeps the logic readable and testable.

Output:
- Writes `src/include/generated_tables.inc`
  (included into the ROM, typically in bank3 with the visible kernel).
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


def bits20_to_pf(bits20: list[int]) -> tuple[int, int, int]:
    """
    Convert 20 playfield bits (left-to-right b0..b19) into PF0/PF1/PF2 bytes.

    Verified against the Alienbill playfield diagram:
    - PF0 uses bits 4..7 and is LSB-first for the 4 displayed pixels: b0->PF0.4 ... b3->PF0.7
    - PF1 is MSB-first: b4->PF1.7 ... b11->PF1.0
    - PF2 is LSB-first: b12->PF2.0 ... b19->PF2.7
    """
    if len(bits20) != 20 or any(b not in (0, 1) for b in bits20):
        raise ValueError("bits20 must be 20 elements of 0/1")

    b = bits20
    pf0 = (b[0] << 4) | (b[1] << 5) | (b[2] << 6) | (b[3] << 7)
    pf1 = 0
    for i in range(8):
        pf1 |= b[4 + i] << (7 - i)
    pf2 = 0
    for i in range(8):
        pf2 |= b[12 + i] << i
    return pf0, pf1, pf2


def bits40_to_pf(bits40: list[int]) -> tuple[int, int, int, int, int, int]:
    if len(bits40) != 40 or any(b not in (0, 1) for b in bits40):
        raise ValueError("bits40 must be 40 elements of 0/1")
    left = bits40[:20]
    right = bits40[20:]
    pf0l, pf1l, pf2l = bits20_to_pf(left)
    pf0r, pf1r, pf2r = bits20_to_pf(right)
    return pf0l, pf1l, pf2l, pf0r, pf1r, pf2r


def byte_list(values: list[int]) -> str:
    return ", ".join(f"${v:02X}" for v in values)


@dataclass(frozen=True)
class PFTable:
    pf0l: list[int]
    pf1l: list[int]
    pf2l: list[int]
    pf0r: list[int]
    pf1r: list[int]
    pf2r: list[int]


def gen_bar_tables() -> PFTable:
    # 16 segments. Each segment is 2 playfield bits.
    # Centered 32-bit bar occupies bits [4..35] of the 40-bit playfield.
    pf0l: list[int] = []
    pf1l: list[int] = []
    pf2l: list[int] = []
    pf0r: list[int] = []
    pf1r: list[int] = []
    pf2r: list[int] = []

    for seg in range(17):  # 0..16
        bits = [0] * 40
        fill_bits = seg * 2
        for i in range(fill_bits):
            bits[4 + i] = 1

        a, b, c, d, e, f = bits40_to_pf(bits)
        pf0l.append(a)
        pf1l.append(b)
        pf2l.append(c)
        pf0r.append(d)
        pf1r.append(e)
        pf2r.append(f)

    return PFTable(pf0l, pf1l, pf2l, pf0r, pf1r, pf2r)


def gen_gear_marker_tables() -> PFTable:
    # Marker positions inside the same centered 32-bit region (bits [4..35]).
    # Six slots at roughly even spacing.
    slots = [2, 7, 12, 17, 22, 27]  # 0..31 inside bar region

    pf0l: list[int] = []
    pf1l: list[int] = []
    pf2l: list[int] = []
    pf0r: list[int] = []
    pf1r: list[int] = []
    pf2r: list[int] = []

    for gear in range(6):
        bits = [0] * 40
        x = 4 + slots[gear]
        # 2-bit wide marker
        bits[x] = 1
        bits[min(39, x + 1)] = 1

        a, b, c, d, e, f = bits40_to_pf(bits)
        pf0l.append(a)
        pf1l.append(b)
        pf2l.append(c)
        pf0r.append(d)
        pf1r.append(e)
        pf2r.append(f)

    return PFTable(pf0l, pf1l, pf2l, pf0r, pf1r, pf2r)


def gen_compass_pointer_tables() -> PFTable:
    """
    Compass strip pointer: 8 directions mapped to 8 pointer positions across the centered 32-bit region.
    Includes cockpit edge frame bits (bit0 and bit39) so it can be drawn on top-strip lines directly.
    """
    pf0l: list[int] = []
    pf1l: list[int] = []
    pf2l: list[int] = []
    pf0r: list[int] = []
    pf1r: list[int] = []
    pf2r: list[int] = []

    # 8 positions across 32-bit region (bits[4..35]) => groups of 4 bits
    for d in range(8):
        bits = [0] * 40
        bits[0] = 1
        bits[39] = 1
        pos = 4 + d * 4 + 1
        bits[pos] = 1
        bits[pos + 1] = 1
        a, b, c, d0, e, f = bits40_to_pf(bits)
        pf0l.append(a)
        pf1l.append(b)
        pf2l.append(c)
        pf0r.append(d0)
        pf1r.append(e)
        pf2r.append(f)

    return PFTable(pf0l, pf1l, pf2l, pf0r, pf1r, pf2r)


def gen_compass_strip_tables() -> PFTable:
    """
    Heading strip: 8 directions worth of playfield for 8 scanlines (64 entries).
    Renders N/NE/E/SE/S/SW/W/NW markers (stylized glyphs) arranged as a
    "heading tape" so that the current direction is centered.
    """

    # 5x5 glyphs per 5-bit slot (8 slots * 5 = 40 bits)
    glyph_N = [
        "10001",
        "11001",
        "10101",
        "10011",
        "10001",
    ]
    glyph_E = [
        "11111",
        "10000",
        "11110",
        "10000",
        "11111",
    ]
    glyph_S = [
        "01111",
        "10000",
        "01110",
        "00001",
        "11110",
    ]
    glyph_W = [
        "10001",
        "10001",
        "10101",
        "11011",
        "10001",
    ]
    glyph_diag = [
        "00000",
        "00100",
        "01110",
        "00100",
        "00000",
    ]

    # Approximate diagonals with a simple marker glyph (still 8-way labeled strip).
    # Order is N,NE,E,SE,S,SW,W,NW (README).
    base_slots = [glyph_N, glyph_diag, glyph_E, glyph_diag, glyph_S, glyph_diag, glyph_W, glyph_diag]

    pf0l: list[int] = []
    pf1l: list[int] = []
    pf2l: list[int] = []
    pf0r: list[int] = []
    pf1r: list[int] = []
    pf2r: list[int] = []

    for view in range(8):
        # Rotate slots so that the current direction is centered.
        # After a fixed 2-bit left rotation (below), slot centers line up at bits 0,5,10,...,35,
        # which puts slot index 4 at the horizontal center (bit 20).
        start = (view - 4) % 8
        slots = base_slots[start:] + base_slots[:start]

        for row in range(8):
            # Rebuild the row from rotated slots so the "tape" moves with view direction.
            if row < 5:
                bits: list[int] = []
                for slot in slots:
                    bits.extend([1 if c == "1" else 0 for c in slot[row]])
                assert len(bits) == 40
            else:
                bits = [0] * 40

            # Rotate whole tape left by 2 bits so slot centers align cleanly with screen center.
            bits = bits[2:] + bits[:2]

            # Bottom scanlines are reserved for a *dynamic* legs-heading dot (added in VBLANK),
            # so we don't bake any underline into the base table.

            a, b, c, d0, e, f = bits40_to_pf(bits)
            pf0l.append(a)
            pf1l.append(b)
            pf2l.append(c)
            pf0r.append(d0)
            pf1r.append(e)
            pf2r.append(f)

    return PFTable(pf0l, pf1l, pf2l, pf0r, pf1r, pf2r)


def gen_gear_ui_tables() -> PFTable:
    """
    Gear selector strip: 6 gears * 5 scanlines (30 entries).
    Renders labels `R2 R1 N 1 2 3` in 6 slots and draws a highlight box around the selected gear.
    """

    # 3x5 glyphs
    glyphs: dict[str, list[str]] = {
        "R": ["111", "101", "111", "110", "101"],
        "N": ["101", "111", "111", "111", "101"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "111", "001", "111"],
        " ": ["000", "000", "000", "000", "000"],
    }

    def glyph_row(ch: str, row: int) -> list[int]:
        s = glyphs[ch][row]
        return [1 if c == "1" else 0 for c in s]

    # Slots are 6 bits wide, with 2-bit margins on each side => 40 bits total
    # slot_start = 2 + slot*6
    slot_labels: list[tuple[str, str]] = [("R", "2"), ("R", "1"), (" ", "N"), (" ", "1"), (" ", "2"), (" ", "3")]

    pf0l: list[int] = []
    pf1l: list[int] = []
    pf2l: list[int] = []
    pf0r: list[int] = []
    pf1r: list[int] = []
    pf2r: list[int] = []

    for gear in range(6):
        for row in range(5):
            bits = [0] * 40
            bits[0] = 1
            bits[39] = 1

            # Text
            for slot in range(6):
                x0 = 2 + slot * 6
                left_ch, right_ch = slot_labels[slot]
                left_bits = glyph_row(left_ch, row)
                right_bits = glyph_row(right_ch, row)
                for i in range(3):
                    bits[x0 + i] = left_bits[i]
                    bits[x0 + 3 + i] = right_bits[i]

            # Highlight box around selected gear slot
            sx0 = 2 + gear * 6
            sx1 = sx0 + 5
            if row in (0, 4):
                for x in range(sx0, sx1 + 1):
                    bits[x] = 1
            else:
                bits[sx0] = 1
                bits[sx1] = 1

            a, b, c, d0, e, f = bits40_to_pf(bits)
            pf0l.append(a)
            pf1l.append(b)
            pf2l.append(c)
            pf0r.append(d0)
            pf1r.append(e)
            pf2r.append(f)

    return PFTable(pf0l, pf1l, pf2l, pf0r, pf1r, pf2r)


def gen_gear_box_tables() -> dict[str, list[int]]:
    """
    Gear selector highlight box: 6 gears * 4 scanlines (top, mid, mid, bottom).
    The box is drawn inside the centered 32-bit region.
    """
    slots = [2, 7, 12, 17, 22, 27]  # 0..31 inside bar region

    out: dict[str, list[int]] = {
        "GearBoxPF0L": [],
        "GearBoxPF1L": [],
        "GearBoxPF2L": [],
        "GearBoxPF0R": [],
        "GearBoxPF1R": [],
        "GearBoxPF2R": [],
    }

    for gear in range(6):
        left = 4 + slots[gear]
        right = left + 3  # 4 PF-bits wide

        for line in range(4):
            bits = [0] * 40

            if line in (0, 3):
                for x in range(left, right + 1):
                    bits[x] = 1
            else:
                bits[left] = 1
                bits[right] = 1

            a, b, c, d0, e, f = bits40_to_pf(bits)
            out["GearBoxPF0L"].append(a)
            out["GearBoxPF1L"].append(b)
            out["GearBoxPF2L"].append(c)
            out["GearBoxPF0R"].append(d0)
            out["GearBoxPF1R"].append(e)
            out["GearBoxPF2R"].append(f)

    return out


def gen_view_overlay_tables() -> dict[str, list[int]]:
    """
    Generate 6*8 entries (tankXIndex 0..4 plus 'none'=5, for 8 scanlines).

    Each entry yields PF bytes for left/right halves.
    """
    # Tank blip x positions as small blocks (40-bit indices).
    # We intentionally make the blip "chunky" to be readable at 2600 resolution.
    tank_blocks: list[tuple[int, int] | None] = [
        (7, 10),    # far left (4 PF bits wide)
        (13, 16),   # left
        (18, 21),   # center
        (23, 26),   # right
        (29, 32),   # far right
        None,       # none
    ]

    def base_frame_bits() -> list[int]:
        bits = [0] * 40
        # narrow cockpit frame on extreme edges
        bits[0] = 1
        bits[39] = 1
        return bits

    out: dict[str, list[int]] = {
        "OverlayPF0L": [],
        "OverlayPF1L": [],
        "OverlayPF2L": [],
        "OverlayPF0R": [],
        "OverlayPF1R": [],
        "OverlayPF2R": [],
    }

    for tank_idx in range(6):
        for line in range(8):
            bits = base_frame_bits()

            # Crosshair vertical line (2-bit wide around center)
            bits[19] = 1
            bits[20] = 1

            # Crosshair horizontal line on middle scanline
            if line == 3:
                for x in range(16, 24):
                    bits[x] = 1

            # Tank blip: chunky block (lines 2..5) to keep it legible.
            block = tank_blocks[tank_idx]
            if block is not None and 2 <= line <= 5:
                for x in range(block[0], block[1] + 1):
                    bits[x] = 1

            a, b, c, d, e, f = bits40_to_pf(bits)
            out["OverlayPF0L"].append(a)
            out["OverlayPF1L"].append(b)
            out["OverlayPF2L"].append(c)
            out["OverlayPF0R"].append(d)
            out["OverlayPF1R"].append(e)
            out["OverlayPF2R"].append(f)

    return out


def gen_horizon_tables() -> PFTable:
    """
    A simple 'mountain ridge' band that shifts smoothly with view heading.
    32 steps (one PF bit per step).
    """
    pf0l: list[int] = []
    pf1l: list[int] = []
    pf2l: list[int] = []
    pf0r: list[int] = []
    pf1r: list[int] = []
    pf2r: list[int] = []

    # 32-bit ridge pattern (center region bits[4..35])
    base = [int(c) for c in "10110111001101011100011101011001"]
    assert len(base) == 32

    for step in range(32):
        shift = step % 32
        # Rotate left so features scroll the same direction as the heading tape during turning.
        ridge = base[shift:] + base[:shift] if shift else base

        bits40 = [0] * 40
        bits40[0] = 1
        bits40[39] = 1
        for i in range(32):
            bits40[4 + i] = ridge[i]

        a, b, c, d0, e, f = bits40_to_pf(bits40)

        pf0l.append(a)
        pf1l.append(b)
        pf2l.append(c)
        pf0r.append(d0)
        pf1r.append(e)
        pf2r.append(f)

    return PFTable(pf0l, pf1l, pf2l, pf0r, pf1r, pf2r)


def gen_map_column_masks() -> dict[str, list[int]]:
    """
    Map columns 0..15 -> PF byte masks for a centered 16-bit map row (bits[12..27]).
    """
    out: dict[str, list[int]] = {
        "MapColPF0LMask": [],
        "MapColPF1LMask": [],
        "MapColPF2LMask": [],
        "MapColPF0RMask": [],
        "MapColPF1RMask": [],
        "MapColPF2RMask": [],
    }

    for col in range(16):
        bits = [0] * 40
        bits[12 + col] = 1
        a, b, c, d, e, f = bits40_to_pf(bits)
        out["MapColPF0LMask"].append(a)
        out["MapColPF1LMask"].append(b)
        out["MapColPF2LMask"].append(c)
        out["MapColPF0RMask"].append(d)
        out["MapColPF1RMask"].append(e)
        out["MapColPF2RMask"].append(f)

    return out


def _emit_tables(lines: list[str], name: str, values: list[int]) -> None:
    """Emit a `.byte` table with nice wrapping for DASM include files."""
    lines.append(f"{name}:")
    for i in range(0, len(values), 16):
        chunk = values[i : i + 16]
        lines.append(f"    .byte {byte_list(chunk)}")
    lines.append("")


def write_kernel_inc(path: Path) -> None:
    """
    Tables required by the visible kernel (bank3).

    Keep this include file as small as possible so bank3 has room for:
    - the visible kernel
    - vectors + bankcall stubs near the end of ROM
    """
    bar = gen_bar_tables()
    compass_strip = gen_compass_strip_tables()
    gear_ui = gen_gear_ui_tables()
    overlay = gen_view_overlay_tables()
    horizon = gen_horizon_tables()

    lines: list[str] = []
    lines.append("; AUTO-GENERATED by tools/gen_tables.py - DO NOT EDIT BY HAND")
    lines.append("; Kernel tables (required during visible scanlines).")
    lines.append("; Playfield bit ordering verified from alienbill playfield diagram.")
    lines.append("")

    # Bars (0..16 segments)
    _emit_tables(lines, "BarPF0L", bar.pf0l)
    _emit_tables(lines, "BarPF1L", bar.pf1l)
    _emit_tables(lines, "BarPF2L", bar.pf2l)
    _emit_tables(lines, "BarPF0R", bar.pf0r)
    _emit_tables(lines, "BarPF1R", bar.pf1r)
    _emit_tables(lines, "BarPF2R", bar.pf2r)

    # Compass strip (8 dirs * 8 lines)
    _emit_tables(lines, "CompassStripPF0L", compass_strip.pf0l)
    _emit_tables(lines, "CompassStripPF1L", compass_strip.pf1l)
    _emit_tables(lines, "CompassStripPF2L", compass_strip.pf2l)
    _emit_tables(lines, "CompassStripPF0R", compass_strip.pf0r)
    _emit_tables(lines, "CompassStripPF1R", compass_strip.pf1r)
    _emit_tables(lines, "CompassStripPF2R", compass_strip.pf2r)

    # Gear UI strip (6 gears * 5 lines)
    _emit_tables(lines, "GearUIPF0L", gear_ui.pf0l)
    _emit_tables(lines, "GearUIPF1L", gear_ui.pf1l)
    _emit_tables(lines, "GearUIPF2L", gear_ui.pf2l)
    _emit_tables(lines, "GearUIPF0R", gear_ui.pf0r)
    _emit_tables(lines, "GearUIPF1R", gear_ui.pf1r)
    _emit_tables(lines, "GearUIPF2R", gear_ui.pf2r)

    # View overlay (tank_idx 0..4 plus none=5) * 8 lines
    for k, v in overlay.items():
        _emit_tables(lines, k, v)

    # Horizon band (32 steps)
    _emit_tables(lines, "HorizonPF0L", horizon.pf0l)
    _emit_tables(lines, "HorizonPF1L", horizon.pf1l)
    _emit_tables(lines, "HorizonPF2L", horizon.pf2l)
    _emit_tables(lines, "HorizonPF0R", horizon.pf0r)
    _emit_tables(lines, "HorizonPF1R", horizon.pf1r)
    _emit_tables(lines, "HorizonPF2R", horizon.pf2r)

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_pause_inc(path: Path) -> None:
    """
    Tables only needed while the game is paused (built during overscan).

    These are intentionally kept out of bank3 so the visible-kernel bank stays small.
    """
    map_masks = gen_map_column_masks()

    lines: list[str] = []
    lines.append("; AUTO-GENERATED by tools/gen_tables.py - DO NOT EDIT BY HAND")
    lines.append("; Pause/map tables (NOT used by the visible kernel).")
    lines.append("; Playfield bit ordering verified from alienbill playfield diagram.")
    lines.append("")

    for k, v in map_masks.items():
        _emit_tables(lines, k, v)

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    out_dir = Path("src/include")
    out_dir.mkdir(parents=True, exist_ok=True)

    kernel_out = out_dir / "generated_kernel_tables.inc"
    pause_out = out_dir / "generated_pause_tables.inc"

    write_kernel_inc(kernel_out)
    write_pause_inc(pause_out)
    print(f"Wrote {kernel_out}")
    print(f"Wrote {pause_out}")


if __name__ == "__main__":
    main()

