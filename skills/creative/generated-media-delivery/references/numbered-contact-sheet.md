# Numbered contact sheet — build recipe

Use when N candidates must be screened by a human who picks by number. Verified working.

## Pipeline

1. **Collect candidates** with a per-item handle (id, url, source) plus a small preview image or a
   frame-fetch recipe for each.
2. **Fetch tiles** in parallel (thread pool, 8–12 workers). Accept a tile only if it downloads and
   is above a small size floor (e.g. > 4 KB) — a truncated fetch renders as a grey cell.
3. **Detect + embed** to pick the best tile and to dedupe identities:
   ```
   uv pip install --python /opt/hermes/venv/bin/python insightface onnxruntime opencv-python-headless
   ```
   ```python
   from insightface.app import FaceAnalysis
   app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])
   app.prepare(ctx_id=-1, det_size=(640,640))
   # per image: largest face by bbox area; keep normed_embedding and det_score
   ```
   The model pack downloads to `/root/.insightface` on first use. If opencv is unavailable, plain
   PIL can still compose the sheet — the embedding step only buys tile ranking and dedupe.
4. **Rank tiles** per candidate by detection score (and by framing label as a tie-break), keeping the
   best-scoring usable tile.
5. **Dedupe identities greedily** — sort by the primary ranking, then skip a candidate whose
   embedding cosine similarity to an already-kept one exceeds the same-subject threshold
   (≈0.42 for ArcFace normed embeddings). Do this BEFORE composing so no subject occupies two cells.
6. **Exclude entities**: blacklist, already-delivered/seen ids, and the domain's widely-known-name
   list — all matched on punctuation-normalized text.
7. **Compose sheets** (below), **deliver** via `MEDIA:`, and post a compact numbered key.

## Composition

```python
from PIL import Image, ImageDraw, ImageFont
CW, CH, cols = 240, 200, 6
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 34)
except Exception:
    font = ImageFont.load_default()   # much smaller; always try truetype first

def sheet(items, start, path):
    rows = (len(items) + cols - 1) // cols
    s = Image.new('RGB', (CW*cols, CH*rows), (18,18,18))
    d = ImageDraw.Draw(s)
    for i, c in enumerate(items):
        r, cc = divmod(i, cols)
        im = Image.open(c['tile']).convert('RGB')
        w, h = im.size; t = CW/CH
        if w/h > t:   # crop the longer dimension, centered
            nw = int(h*t); im = im.crop(((w-nw)//2, 0, (w-nw)//2+nw, h))
        else:
            nh = int(w/t); im = im.crop((0, (h-nh)//2, w, (h-nh)//2+nh))
        im = im.resize((CW, CH))
        s.paste(im, (cc*CW, r*CH))
        n = start + i                     # contiguous across sheets
        d.rectangle([cc*CW+4, r*CH+4, cc*CW+54, r*CH+48], fill=(0,0,0))
        d.text((cc*CW+13, r*CH+6), str(n), fill=(255,255,0), font=font)
    s.save(path, quality=82)
```

- Split at ~22 items per sheet; keep each file under ~250 KB (lower `quality`, or shrink the cell)
  so the platform sends it as a photo rather than a document.
- Numbering is the contract: the user's reply is a list of numbers, so any off-by-one or restart
  makes their answer unresolvable. Number once, from the ordered list you will keep.
- Persist the ordered index (`[{num, id, url, meta}]`) alongside the sheets so the numbers can be
  resolved after the fact without re-deriving the order.

## Verification pitfalls that silently empty or corrupt a sheet

- **Greedy JSON regex over a CLI-style output.** `re.search(r'\{.*\}', stdout, re.S)` swallows any
  trailing status line (e.g. a `USAGE {...}` block) and raises `JSONDecodeError: Extra data`, which
  a naive `except` turns into «no face found» for EVERY item. Use a non-greedy `r'\{.*?\}'` or take
  the first line only.
- **Self-inclusion in a validation set.** When measuring whether a set separates into groups, never
  compare an item against a reference set that CONTAINS that item — self-similarity ≈ 1.0 forces
  every margin to one side and manufactures a fake separation. Always leave-one-out, and verify the
  metric on items that are not in the reference set.
- **Report the measured separation before trusting any group metric**, and if the held-out means
  point the wrong way, the instrument is dead — say so rather than tuning the threshold until it
  looks right.
