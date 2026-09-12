#!/usr/bin/env python3
"""viz_render.py — extra code-render routes: mermaid, markmap, plotly.

All three run through the SAME headless chromium that already works on this box,
using JS bundles stored locally in ~/.hermes/assets/viz/ (no CDN at render time,
no node, no npm, no apt).

    viz_render.py mermaid <code.mmd|-> <out.png> [--width 1200]
    viz_render.py markmap <file.md|-> <out.png>   [--width 1100 --height 800]
    viz_render.py plotly-html <file.html> <out.png> [--width 1200]

Chromium flags that matter:
  --allow-file-access-from-files  else <script src="file://..."> is blocked
  --virtual-time-budget=6000      lets mermaid/markmap finish before the shot
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile

ASSETS = os.path.expanduser("~/.hermes/assets/viz")
CHROMIUM = ("/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome")

PAGE = """<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
 body{{margin:0;background:#fff;font-family:"Nimbus Sans",Helvetica,Arial,sans-serif}}
 .wrap{{padding:26px 30px}}
</style></head><body><div class="wrap">{body}</div>{scripts}</body></html>"""


def chromium() -> str:
    for c in CHROMIUM:
        if os.path.exists(c):
            return c
    raise SystemExit("no chromium binary")


def shoot(html: str, out: str, w: int, h: int) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(html)
        path = f.name
    try:
        subprocess.run([chromium(), "--headless", "--disable-gpu", "--no-sandbox",
                        "--hide-scrollbars", "--allow-file-access-from-files",
                        "--virtual-time-budget=6000", "--force-device-scale-factor=2",
                        f"--window-size={w},{h}", f"--screenshot={out}", "file://" + path],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        os.unlink(path)
    trim(out)
    print("RENDERED:", out, os.path.getsize(out), "bytes")


def trim(path: str) -> None:
    try:
        from PIL import Image
    except ImportError:
        return
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    b = h - 1
    while b > 10:
        row = [px[x, b] for x in range(0, w, max(1, w // 60))]
        if len(set(row)) > 1:
            break
        b -= 1
    if b + 14 < h:
        im.crop((0, 0, w, b + 14)).save(path)


def mermaid(code: str, out: str, w: int) -> None:
    scripts = (f'<script src="file://{ASSETS}/mermaid.min.js"></script>'
               '<script>mermaid.initialize({startOnLoad:true,theme:"base",'
               'themeVariables:{fontFamily:"Nimbus Sans, Helvetica, Arial",'
               'primaryColor:"#ffffff",primaryBorderColor:"#dcdcdc",'
               'primaryTextColor:"#141414",lineColor:"#B4472E",fontSize:"15px"}});</script>')
    body = f'<pre class="mermaid">{code}</pre>'
    shoot(PAGE.format(body=body, scripts=scripts), out, w, 1400)


def markmap(md: str, out: str, w: int, h: int) -> None:
    # Explicit init (NOT the autoloader): the autoloader animates the layout and the
    # screenshot beat it, leaving only the root text. duration:0 renders immediately.
    scripts = (f'<script src="file://{ASSETS}/d3.min.js"></script>'
               f'<script src="file://{ASSETS}/markmap-view.js"></script>'
               f'<script src="file://{ASSETS}/markmap-lib.js"></script>'
               '<script>\n'
               'window.addEventListener("load", function(){\n'
               '  try{\n'
               '    const {Transformer, Markmap} = window.markmap;\n'
               '    const md = document.getElementById("src").textContent;\n'
               '    const {root} = new Transformer().transform(md);\n'
               '    const svg = document.getElementById("mm");\n'
               '    Markmap.create(svg, {duration: 0, autoFit: true, spacingVertical: 8,\n'
               '                         spacingHorizontal: 90, paddingX: 14, colorFreezeLevel: 2}, root);\n'
               '    document.title = "markmap-ok";\n'
               '  }catch(e){ document.body.insertAdjacentHTML("beforeend",\n'
               '      "<pre style=\'color:#b00\'>MARKMAP ERROR: "+e+"</pre>"); }\n'
               '});\n'
               '</script>')
    body = (f'<svg id="mm" style="width:{w-70}px;height:{h-60}px"></svg>'
            f'<script type="text/plain" id="src">{md}</script>')
    shoot(PAGE.format(body=body, scripts=scripts), out, w, h)


def plotly_html(path: str, out: str, w: int, h: int) -> None:
    shoot(open(path, encoding="utf-8").read(), out, w, h)


def kroki(diagram_type: str, source: str, out: str, w: int, h: int) -> None:
    """Render a diagram over HTTP via Kroki — 20+ languages, NO local binary.

    Found through /firebrowsing 2026-09-11 and verified live:
      graphviz ✓ (3121 B SVG) · d2 ✓ (11305 B) · plantuml ✓ (5006 B)
    This is how graphviz/PlantUML/D2 become usable on a box with no apt, no Java
    and no graphviz binary — the same tools that had to be rejected before.
    """
    import urllib.request
    req = urllib.request.Request(
        f"https://kroki.io/{diagram_type}/svg", data=source.encode("utf-8"),
        # kroki.io answers 403 to the default urllib UA (curl works) — send a real one.
        headers={"Content-Type": "text/plain",
                 "Accept": "image/svg+xml,text/plain,*/*",
                 "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) hermes-viz/1.0"},
        method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        svg = r.read().decode("utf-8", "replace")
    if not svg.lstrip().startswith("<?xml") and "<svg" not in svg[:200]:
        raise SystemExit(f"kroki returned non-SVG: {svg[:200]}")
    tmp = tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False, encoding="utf-8")
    tmp.write(svg)
    tmp.close()
    try:
        # browser is the rasterizer; print background + margins come from the SVG itself
        shoot(f'<img src="file://{tmp.name}" style="display:block">', out, w, h)
    finally:
        os.unlink(tmp.name)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["mermaid", "markmap", "plotly-html", "kroki"])
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--type", default="graphviz",
                    help="kroki diagram type: graphviz, d2, plantuml, mermaid, nomnoml, svgbob, wavedrom, ...")
    ap.add_argument("--width", type=int, default=1200)
    ap.add_argument("--height", type=int, default=800)
    a = ap.parse_args()
    data = sys.stdin.read() if a.src == "-" else open(a.src, encoding="utf-8").read()
    if a.mode == "mermaid":
        mermaid(data, a.out, a.width)
    elif a.mode == "markmap":
        markmap(data, a.out, a.width, a.height)
    elif a.mode == "kroki":
        kroki(a.type, data, a.out, a.width, max(a.height, 700))
    else:
        plotly_html(a.src, a.out, a.width, a.height)
    return 0


if __name__ == "__main__":
    sys.exit(main())
