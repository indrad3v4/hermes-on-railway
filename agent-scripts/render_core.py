#!/usr/bin/env python3
"""render_core.py — the «core message» card: one code-rendered visual per reply.

Indra's rule (2026-09-11, tightened 2026-09-12): the CARD carries the answer.
Prose is a caption, not the payload — fewer tokens to him, better visual.

Rendered with code (HTML -> headless Chromium -> PNG): exact text, $0, no model.

Usage
-----
    render_core.py --kick..." --core "..." --status ok \
                   --lines "..." --foot "next step" -o out.png
    render_core.py --check

--lines mini-syntax (pipe-separated, order preserved):
    #LABEL            -> section label (small caps, tracked)
    key :: value      -> two-column row (label muted left, value ink right)
    anything else     -> bullet line
Inline markup: **bold** -> accent+heavy (use on the one number that matters)

Design tokens: accent #B4472E, ink #141414, muted #6f6f6f, hairline #e2e2e2,
white bg, Nimbus Sans (Helvetica metrics), no gradients, no stock icons,
no decorative shadows. Semantic status tones are the single allowed exception
to the one-accent rule (they encode verdict, not decoration).
"""
from __future__ import annotations

import argparse
import html
import os
import re
import subprocess
import sys
import tempfile

CHROMIUM = ("/usr/bin/chromium", "/usr/bin/chromium-browser",
            "/usr/bin/google-chrome", "/usr/bin/google-chrome-stable")

STATUS = {
    "ok":    ("ok",    "\u2713", "РАБОТАЕТ"),
    "warn":  ("warn",  "!",      "ВНИМАНИЕ"),
    "bad":   ("bad",   "\u2715", "БЛОК"),
    "info":  ("info",  "\u00b7", "ИНФО"),
    "none":  (None,    "",       ""),
}

TEMPLATE = """<!DOCTYPE html>
<html lang="ru"><head><meta charset="utf-8"><style>
  :root{{--ink:#141414;--mut:#6f6f6f;--line:#e2e2e2;--acc:#B4472E;
        --ok:#2F6B4F;--warn:#A9741F;--bad:#B4472E;--bg:#fff}}
  *{{box-sizing:border-box;margin:0;padding:0}}
  html{{overflow:hidden}}
  body{{background:var(--bg);color:var(--ink);width:1240px;overflow:hidden;
        font-family:"Nimbus Sans","Helvetica Neue",Helvetica,Arial,sans-serif;
        padding:42px 54px 40px}}
  header{{display:flex;align-items:center;justify-content:space-between;
          gap:20px;margin-bottom:20px}}
  .kicker{{font-size:12.5px;letter-spacing:.18em;text-transform:uppercase;
           color:var(--acc);font-weight:700}}
  .chip{{font-size:12.5px;font-weight:700;letter-spacing:.12em;
         text-transform:uppercase;padding:7px 14px;border-radius:3px;
         border:1.5px solid currentColor;white-space:nowrap}}
  .chip.ok{{color:var(--ok);background:rgba(47,107,79,.07)}}
  .chip.warn{{color:var(--warn);background:rgba(169,116,31,.08)}}
  .chip.bad{{color:var(--bad);background:rgba(180,71,46,.07)}}
  .chip.info{{color:var(--mut);background:rgba(111,111,111,.07)}}
  .core{{font-size:{core_size}px;line-height:1.16;font-weight:700;
         letter-spacing:-.018em;max-width:1130px;
         text-wrap:balance;overflow-wrap:break-word}}
  b{{color:var(--acc)}}
  .rule{{height:1px;background:var(--line);margin:26px 0 0}}
  section{{margin-top:18px}}
  .label{{font-size:12px;letter-spacing:.18em;text-transform:uppercase;
          color:#5a5a5a;font-weight:700;margin:0 0 9px}}
  .row{{display:flex;align-items:baseline;gap:14px;padding:6px 0;
        border-bottom:1px solid #f2f2f2}}
  .row:last-child{{border-bottom:none}}
  .row .k{{flex:0 0 218px;color:var(--mut);font-size:15.5px}}
  .row .v{{font-size:17.5px;line-height:1.4;color:#1f1f1f}}
  .row .v b{{font-weight:700}}
  .bul{{font-size:17.5px;line-height:1.45;color:#2b2b2b;
        padding:5px 0 5px 24px;position:relative}}
  .bul:before{{content:"";position:absolute;left:0;top:15px;width:10px;height:2px;
               background:var(--acc)}}
  footer{{margin-top:26px;padding-top:16px;border-top:1px solid var(--line);
          font-size:16px;color:var(--mut)}}
  footer b{{color:var(--ink)}}
</style></head><body>
  <header>
    <div class="kicker">{kicker}</div>{chip}
  </header>
  <div class="core">{core}</div>
  <div class="rule"></div>
  {body}
  {foot}
</body></html>"""


def find_chromium() -> str | None:
    for c in CHROMIUM:
        if os.path.exists(c):
            return c
    return None


def md(text: str) -> str:
    """Escape, then apply the tiny **bold** markup."""
    out = html.escape(text)
    return re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", out)


def core_size(core: str) -> int:
    n = len(core)
    if n <= 46:
        return 40
    if n <= 80:
        return 34
    if n <= 130:
        return 29
    return 25


def build_body(lines: list[str]) -> str:
    parts: list[str] = []
    buf: list[str] = []

    def flush() -> None:
        if not buf:
            return
        parts.append('<section>' + "".join(buf) + "</section>")
        buf.clear()

    for raw in lines:
        s = raw.strip()
        if not s:
            continue
        if s.startswith("#"):
            flush()
            parts.append(f'<div class="label" style="margin-top:24px">'
                         f'{html.escape(s[1:].strip())}</div>')
            continue
        if "::" in s:
            k, v = s.split("::", 1)
            buf.append(f'<div class="row"><span class="k">{md(k.strip())}</span>'
                       f'<span class="v">{md(v.strip())}</span></div>')
        else:
            buf.append(f'<div class="bul">{md(s)}</div>')
    flush()

    # sections that consist only of a label: rewrap any bare label markup
    out = "".join(parts)
    return out.replace('</section><div class="label"', '<div class="label"')


def build_html(kicker: str, core: str, lines: list[str],
               status: str, foot: str) -> str:
    cls, sym, word = STATUS.get(status, STATUS["none"])
    chip = ""
    if cls:
        chip = f'<div class="chip {cls}">{sym} {html.escape(word)}</div>'
    body = build_body(lines)
    foot_html = f"<footer>{md(foot)}</footer>" if foot.strip() else ""
    return TEMPLATE.format(
        kicker=html.escape(kicker), chip=chip, core=md(core),
        core_size=core_size(core), body=body, foot=foot_html,
    )


def render(chrom: str, html_text: str, out: str, width: int, height: int) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False,
                                     encoding="utf-8") as f:
        f.write(html_text)
        path = f.name
    try:
        subprocess.run(
            [chrom, "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
             "--force-device-scale-factor=2", f"--window-size={width},{height}",
             f"--screenshot={out}", "file://" + path],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    finally:
        os.unlink(path)


def trim(path: str) -> None:
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
    cut = min(h, bottom + 16)
    if cut < h:
        im.crop((0, 0, w, cut)).save(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kicker", default="Core message")
    ap.add_argument("--core", required=False)
    ap.add_argument("--lines", default="")
    ap.add_argument("--status", default="none", choices=sorted(STATUS))
    ap.add_argument("--foot", default="")
    ap.add_argument("-o", "--out", required=False)
    ap.add_argument("--width", type=int, default=1240)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    chrom = find_chromium()
    if a.check or not a.core:
        print("chromium:", chrom or "NOT FOUND")
        return 0 if chrom else 1
    if not chrom:
        print("ERROR: no chromium binary", file=sys.stderr)
        return 1

    lines = [l for l in a.lines.split("|")]
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    render(chrom, build_html(a.kicker, a.core, lines, a.status, a.foot),
           a.out, a.width, 1000)
    trim(a.out)
    print("CORE CARD:", a.out, f"{os.path.getsize(a.out)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
