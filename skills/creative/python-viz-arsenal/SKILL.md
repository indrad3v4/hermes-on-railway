---
name: python-viz-arsenal
description: "Use when drawing charts, graphs, maps, or documents in code."
version: 1.0.0
---

# Python Viz Arsenal — programmatic drawing

Indra's rule: **draw with code, never with layout tools.** This skill is the catalog of
the 20 Python libraries baked into the image (see `hermes-on-railway/Dockerfile`) and
the protocol for producing a verified visual artifact from any of them.

## When to use

- A chart, graph, map, or document must be generated as a PNG/SVG/PDF artifact.
- The output is consumed by a client, a post, a report, or a core-card.
- The shape is known in advance (not exploratory — for that, use a notebook).

## When NOT to use

- Interactive web UIs → `p5js` / `sketch` / `reflex-web-ops`.
- ASCII-only output → `ascii-art`.
- Photo/illustration generation → `genai-image-prompting` / `comfyui`.
- Architecture diagrams → `architecture-diagram` (different grammar).

## The arsenal (baked into the image)

| Category | Library | Best for |
|---|---|---|
| **charts** | `matplotlib` | full control, publication |
| | `seaborn` | statistical, quick |
| | `plotly` + `kaleido` | interactive→static |
| | `altair` + `vl-convert-python` | declarative |
| | `pygal` | SVG sparklines |
| **graphs** | `networkx` + `graphviz` + `pydot` | relational |
| | `diagrams` | cloud/infra |
| **SVG** | `svgwrite` | raw SVG |
| | `drawsvg` | animated SVG |
| | `schemdraw` | circuits/flow |
| **maps** | `geopandas` + `folium` | geo |
| **raster** | `wordcloud` | word clouds |
| | `pywaffle` | waffle charts |
| | `squarify` | treemaps |
| **tables** | `tabulate` + `prettytable` | text tables |
| **documents** | `fpdf2` | PDF |
| | `img2pdf` | images→PDF |
| | `svglib` | SVG→PDF |
| | `xlsxwriter` / `openpyxl` | Excel |

## Protocol

1. **Pick the library** from the table above. If two fit, prefer the one with fewer
dependencies (e.g. `matplotlib` over `plotly` for a simple bar chart).
2. **Smoke-render** — run a minimal script that produces the artifact and verify the
file is >0 bytes. Never claim success without a real file on disk.
3. **QA the artifact** — open it with `vision_analyze` and check: text is readable,
colors are distinct, nothing is clipped, no overlapping labels.
4. **Deliver** — `MEDIA:/absolute/path/to/file.png` (or `.svg`, `.pdf`). Never describe
what the image shows; the user sees it.

## Smoke-render template

```python
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

fig, ax = plt.subplots(figsize=(8, 4))
ax.bar(["a", "b", "c"], [1, 2, 3])
fig.savefig("/tmp/smoke.png", dpi=150, bbox_inches="tight")
print("OK")
```

Run with `/opt/hermes/venv/bin/python3` (the venv has all 20 libs).

## Anti-patterns

- Do NOT import a library not in the table above — it is not in the image and the
script will fail at runtime.
- Do NOT use `plt.show()` — there is no display; always `savefig`.
- Do NOT hand-craft SVG when `svgwrite` or `schemdraw` can do it.
- Do NOT generate a chart when a `tabulate` table communicates the same thing.
- Do NOT skip the smoke-render — a script that ran is not the same as a script that
produced a file.
