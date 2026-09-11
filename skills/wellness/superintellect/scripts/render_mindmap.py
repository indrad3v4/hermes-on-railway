#!/usr/bin/env python3
"""Render Indra's Superintellect mind-map (10 Buzan sub-intellects) via matplotlib.

Usage:
    python render_mindmap.py
Renders to media/cards/superintellect-mindmap-<ts>.png (dark theme, radial layout).

Reusable by any session that needs to visualize the 10-sub-intellect ring.
The skill 'superintellect' tracks the development protocol; this script only draws it.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Ellipse
import numpy as np, os, datetime

SUBI = [
    ("LOGICAL",   "Math, logic,\nsequences"),
    ("SPATIAL",   "Mind-maps, diagrams,\nvisual synthesis"),
    ("CREATIVE",  "Ideas, metaphors,\nleaps across domains"),
    ("LINGUISTIC","Verbal precision,\nrhetoric, stories"),
    ("MEMORY",    "Recall, anchors,\nspaced structure"),
    ("PERSONAL",  "Drive, habits,\nsystems of action"),
    ("SOCIAL",    "Reading people,\nteam synergy"),
    ("MUSICAL",   "Rhythm, patterns,\nflow-state craft"),
    ("NATURALIST","Systems sensing,\nfeedback reading"),
    ("SPIRITUAL", "Values, vision,\npurpose alignment"),
]
COLORS = ["#4e79a7","#f28e2b","#e15759","#76b7b2","#59a14f",
          "#af7a0e","#b07aa1","#e181a6","#7970ce","#af8186"]
TAGS = [("charts","#4e79a7"),("diagrams","#f28e2b"),("networks","#e15759"),
        ("maps","#76b7b2"),("3D","#59a14f"),("animated","#af7a0e"),
        ("infographic","#b07aa1"),("print","#e181a6"),("tables","#7970ce")]

def main():
    OUT = "/root/.hermes/media/cards"
    os.makedirs(OUT, exist_ok=True)
    fig, ax = plt.subplots(figsize=(21, 14), facecolor="#0e0f14")
    ax.set_xlim(0, 21); ax.set_ylim(0, 14); ax.axis("off")
    cx, cy = 10.5, 7.0
    ax.add_patch(Ellipse((cx, cy), 2.6, 2.6, facecolor="#ffd86b",
            edgecolor="#523014", lw=2.5, zorder=10, alpha=0.97))
    for i, (name, desc) in enumerate(SUBI):
        ang = np.pi/2 + 2*np.pi*i/len(SUBI)
        bx, by = cx + 5.0*np.cos(ang), cy + 5.0*np.sin(ang)
        ell = FancyBboxPatch((bx-0.95, by-0.6), 1.9, 1.2,
            boxstyle="round,pad=0.08,rounding_size=0.25",
            facecolor=COLORS[i], alpha=0.92, edgecolor="white", lw=1.6, zorder=6)
        ax.add_patch(ell)
        ax.text(bx, by+0.15, name, ha="center", va="center",
                fontsize=8, fontweight="bold", color="white", family="monospace")
        ax.text(bx, by-0.32, desc, ha="center", va="center",
                fontsize=5.8, color="white", alpha=0.85, linespacing=1.2)
        ax.plot([cx, bx],[cy, by], color="#444850", lw=0.9, zorder=1, alpha=0.7)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out = f"{OUT}/superintellect-mindmap-{ts}.png"
    plt.savefig(out, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
    print(out)

if __name__ == "__main__":
    main()
