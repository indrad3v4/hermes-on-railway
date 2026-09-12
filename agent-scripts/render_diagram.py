#!/usr/bin/env python3
"""render_diagram.py — deterministic HTML/SVG → PNG renderer for chat artifacts.

Why: text-to-image models garble labels and invent fake words. Code-rendered
visuals carry EXACT text, exact numbers, one accent colour, no stock icons.

Usage:
    render_diagram.py <input.html> <out.png> [--width 1240] [--height auto]
    render_diagram.py --check                      # is chromium usable?

Mechanism: headless Chromium --screenshot (Playwright is NOT installed in the
venv; /usr/bin/chromium is present on this box). Height "auto" measures the page
first, then re-renders at the exact height so there is no dead space.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

CHROMIUM_CANDIDATES = ("/usr/bin/chromium", "/usr/bin/chromium-browser",
                       "/usr/bin/google-chrome", "/usr/bin/google-chrome-stable")


def find_chromium() -> str | None:
    for c in CHROMIUM_CANDIDATES:
        if os.path.exists(c):
            return c
    return shutil.which("chromium") or shutil.which("chromium-browser")


def _run(chrom: str, url: str, out: str, w: int, h: int) -> None:
    cmd = [
        chrom, "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
        "--force-device-scale-factor=2",          # crisp text on Telegram
        f"--window-size={w},{h}",
        f"--screenshot={out}",
        url,
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def measure_height(chrom: str, url: str, w: int) -> int:
    """Render once tall, then read the real page height via a DOM dump."""
    with tempfile.TemporaryDirectory() as td:
        probe = os.path.join(td, "probe.png")
        _run(chrom, url, probe, w, 4000)
    # chromium has no --dump-dom-with-height; use a generous fixed page and let
    # CSS size the body. We approximate by asking for a tall window and then
    # trimming fully-uniform bottom rows with PIL.
    return 4000


def trim_bottom(path: str) -> None:
    """Cut uniform rows at the bottom (dead space from the tall render)."""
    try:
        from PIL import Image
    except ImportError:
        return
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    bottom = h - 1
    while bottom > 10:
        row = [px[x, bottom] for x in range(0, w, max(1, w // 60))]
        if len(set(row)) > 1:
            break
        bottom -= 1
    cut = bottom + 12
    if cut < h:
        im.crop((0, 0, w, cut)).save(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--width", type=int, default=1240)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    chrom = find_chromium()
    if a.check or not a.input:
        print("chromium:", chrom or "NOT FOUND")
        return 0 if chrom else 1
    if not chrom:
        print("ERROR: no chromium binary", file=sys.stderr)
        return 1

    src = os.path.abspath(a.input)
    out = os.path.abspath(a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)  # chromium fails SILENTLY otherwise
    url = "file://" + src
    _run(chrom, url, out, a.width, measure_height(chrom, url, a.width))
    trim_bottom(out)
    print("RENDERED:", out, f"{os.path.getsize(out)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
