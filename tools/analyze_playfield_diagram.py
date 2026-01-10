"""
Utility to help verify Atari 2600 playfield bit ordering from a diagram image.

This project uses an asymmetric playfield kernel and generates PF0/PF1/PF2 bytes
from "human" 40-bit rows. Since PF0/PF2 have reversed bit ordering vs PF1,
it's easy to get confused.

This script samples `tools/playfield.gif` and prints the inferred left/right
bit patterns so we can cross-check our bit-to-PF mapping code.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image


@dataclass(frozen=True)
class SampleResult:
    width: int
    height: int
    bar_y: int
    bar_x0: int
    bar_x1: int
    blocks: int
    block_width: float
    bits: str


def sample_bits(img_path: Path, blocks: int) -> SampleResult:
    """
    Sample the colored block bar in the diagram as N evenly-spaced blocks.

    Parameters:
    - img_path: path to the GIF/PNG diagram
    - blocks: number of blocks to sample (20 for half PF, 40 for full line)
    """
    img = Image.open(img_path).convert("RGB")
    w, h = img.size

    # Find a row that likely contains the block bar: max non-white pixels.
    best_y = 0
    best_count = -1
    for y in range(h):
        nonwhite = 0
        for x in range(w):
            r, g, b = img.getpixel((x, y))
            if r < 250 or g < 250 or b < 250:
                nonwhite += 1
        if nonwhite > best_count:
            best_count = nonwhite
            best_y = y

    # Find contiguous x-range of non-white pixels on that row.
    xs = []
    for x in range(w):
        r, g, b = img.getpixel((x, best_y))
        if r < 250 or g < 250 or b < 250:
            xs.append(x)
    x0, x1 = min(xs), max(xs)

    bw = (x1 - x0 + 1) / blocks

    def is_red(rgb: tuple[int, int, int]) -> bool:
        r, g, b = rgb
        return r > 150 and g < 120 and b < 120

    bits = []
    for i in range(blocks):
        x = int(x0 + (i + 0.5) * bw)
        bits.append("1" if is_red(img.getpixel((x, best_y))) else "0")

    return SampleResult(
        width=w,
        height=h,
        bar_y=best_y,
        bar_x0=x0,
        bar_x1=x1,
        blocks=blocks,
        block_width=bw,
        bits="".join(bits),
    )


def main() -> None:
    """Print sampled bit patterns for both 20-block and 40-block interpretations."""
    img_path = Path("tools/playfield.gif")
    if not img_path.exists():
        raise SystemExit(f"Missing {img_path}; download it first.")

    for blocks in (20, 40):
        res = sample_bits(img_path, blocks=blocks)
        print(f"Image: {img_path} ({res.width}x{res.height})")
        print(f"bar_y={res.bar_y} bar_x=[{res.bar_x0},{res.bar_x1}] width={res.bar_x1-res.bar_x0+1}")
        print(f"blocks={res.blocks} block_width={res.block_width:.2f}")
        print(f"bits{blocks}: {res.bits}")
        if blocks == 40:
            print(f" left20: {res.bits[:20]}")
            print(f"right20: {res.bits[20:]}")
        print()


if __name__ == "__main__":
    main()

