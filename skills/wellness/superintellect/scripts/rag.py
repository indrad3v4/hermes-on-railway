#!/usr/bin/env python3
"""rag.py — local, dependency-light retrieval over the superintellect corpus.

Why: the skill must RETRIEVE the Superintellect material instead of recalling it.
No API, no embeddings server, no new heavy deps — scikit-learn is already on the
box. Character n-grams make it language-agnostic (RU / BE / EN in one index).

Index location: ~/.hermes/media/rag/superintellect/  (index.npz + meta.json)

Usage:
    rag.py build                       # (re)index corpus/ + any extra dirs
    rag.py query "mind map weakest link" -k 4
    rag.py stats
    rag.py add <path>                  # copy a text/pdf-txt file into corpus/ and rebuild
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import pickle
import shutil
import sys

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS_DIR = os.path.join(SKILL_DIR, "corpus")
EXTRA_DIRS = [
    "/root/.hermes/dvizhok/research",  # research distillations (buzan-superintellect.md)
]
INDEX_DIR = os.path.expanduser("~/.hermes/media/rag/superintellect")
CHUNK, OVERLAP = 900, 150
TEXT_EXT = (".md", ".txt", ".markdown")


def chunk_text(text: str, size: int = CHUNK, overlap: int = OVERLAP):
    text = " ".join(text.split())
    out, i = [], 0
    while i < len(text):
        piece = text[i:i + size]
        if len(piece.strip()) > 80:
            out.append(piece.strip())
        i += size - overlap
    return out


def collect():
    docs = []
    seen = set()
    for d in [CORPUS_DIR] + EXTRA_DIRS:
        if not os.path.isdir(d):
            continue
        for p in sorted(glob.glob(os.path.join(d, "**", "*"), recursive=True)):
            if not p.endswith(TEXT_EXT) or os.path.isdir(p):
                continue
            # only the Buzan material from the shared research dir
            if d != CORPUS_DIR and "buzan" not in os.path.basename(p).lower():
                continue
            if p in seen:
                continue
            seen.add(p)
            try:
                with open(p, encoding="utf-8") as f:
                    raw = f.read()
            except Exception:
                continue
            for j, ch in enumerate(chunk_text(raw)):
                docs.append({"src": os.path.relpath(p, "/root"), "n": j, "text": ch})
    return docs


def build() -> int:
    try:
        from sklearn.feature_extraction.text import TfidfVectorizer
    except ImportError:
        print("ERROR: scikit-learn missing", file=sys.stderr)
        return 1
    docs = collect()
    if not docs:
        print("ERROR: corpus empty — put .md/.txt into", CORPUS_DIR, file=sys.stderr)
        return 1
    vec = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), min_df=1,
                          sublinear_tf=True, max_features=200_000)
    X = vec.fit_transform([d["text"] for d in docs])
    os.makedirs(INDEX_DIR, exist_ok=True)
    with open(os.path.join(INDEX_DIR, "index.pkl"), "wb") as f:
        pickle.dump({"vec": vec, "X": X}, f)
    with open(os.path.join(INDEX_DIR, "meta.json"), "w") as f:
        json.dump({"docs": docs, "n_chunks": len(docs),
                   "sources": sorted({d["src"] for d in docs})}, f, ensure_ascii=False, indent=1)
    print(f"INDEXED {len(docs)} chunks from {len({d['src'] for d in docs})} sources -> {INDEX_DIR}")
    return 0


def load():
    with open(os.path.join(INDEX_DIR, "index.pkl"), "rb") as f:
        blob = pickle.load(f)
    with open(os.path.join(INDEX_DIR, "meta.json"), encoding="utf-8") as f:
        meta = json.load(f)
    return blob, meta


def query(q: str, k: int) -> int:
    from sklearn.metrics.pairwise import cosine_similarity
    blob, meta = load()
    sims = cosine_similarity(blob["vec"].transform([q]), blob["X"])[0]
    order = sims.argsort()[::-1][:k]
    for rank, idx in enumerate(order, 1):
        d = meta["docs"][idx]
        print(f"\n[{rank}] score={sims[idx]:.3f}  src={d['src']}  chunk#{d['n']}")
        print("    " + d["text"][:600].replace("\n", " "))
    return 0


def stats() -> int:
    try:
        _, meta = load()
    except Exception as e:
        print("no index yet:", e)
        return 1
    print("chunks:", meta["n_chunks"])
    for s in meta["sources"]:
        print("  -", s)
    return 0


def add(path: str) -> int:
    os.makedirs(CORPUS_DIR, exist_ok=True)
    dest = os.path.join(CORPUS_DIR, os.path.basename(path))
    shutil.copy(path, dest)
    print("added:", dest)
    return build()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["build", "query", "stats", "add"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("-k", type=int, default=4)
    a = ap.parse_args()
    if a.cmd == "build":
        return build()
    if a.cmd == "query":
        return query(a.arg or "", a.k)
    if a.cmd == "stats":
        return stats()
    return add(a.arg or "")


if __name__ == "__main__":
    sys.exit(main())
