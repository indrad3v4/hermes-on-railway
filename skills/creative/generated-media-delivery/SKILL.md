---
name: generated-media-delivery
description: "Use when delivering generated images to the user."
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [delivery, telegram, image, media, fal, post-processing, typography]
    category: creative
---

# Generated Media Delivery

How to get a generated image/video from the generation tool into the user's
hands (Telegram-first box). Learned the hard way 2026-09-05: Indra asked to
SEE a fal-generated key visual 5× in one session («верні картінку», «скінь
сюда», «ну і шо там?», «What skill you can use to return visual …?») while
the assistant kept answering with vision_analyze descriptions instead of the
file. Each unanswered delivery cost trust.

## Core rule

**User asks to see/send a generated image → the reply MUST contain
`MEDIA:/absolute/path.png` on its own line.** The image IS the deliverable.
A vision_analyze summary is NOT a substitute — it is a QA step, never the answer.

- Generate → save locally → verify (size + magic bytes, or vision_analyze for
  content) → reply with `MEDIA:<path>` on its own line.
- When the user re-asks for the image a second time, STOP re-describing — the
  MEDIA: line was missing or the platform didn't render it. Send it.
- `/skills` does not return images; `MEDIA:` is the mechanism (docs: send files
  natively with `MEDIA:/abs/path`).

## Programmatic text overlay (brand key visual pattern)

- Generate WITHOUT in-image text: add «no text, no logos, no signature» to the
  prompt (flux-2/klein garbles small text into fake words).
- Add typography with PIL afterwards:
  - `apt-get install -y fonts-urw-base35` → Nimbus Sans = Helvetica-metric
    (real Helvetica is commercial; Nimbus Sans is the standard metric-compatible
    substitute). Liberation Sans (fonts-liberation2) is Arial-metric — second choice.
  - Pattern that works: brand wordmark top-left in graphite (#1C1C1E), tagline
    bottom on a subtle semi-transparent dark strip, text color warm ivory
    (#F5F4F0). Use `draw.textbbox` to measure before placing.
  - Verify the composite with vision_analyze before delivering (reads every
    text element, checks nothing overlaps the subject).

## Event/calendar poster in two layers (layout grid + code overlay) — proven 2026-09-09

For a month-program poster (giant hero + a row of N event boxes/date frames),
do NOT ask the model to render the row of frames at all:

- **Generative models cannot count.** Asked for "exactly six empty calendar
  frames" it returned 5, then 7 — flux/klein has no reliable 1-to-N grip. Never
  burn generations iterating toward a specific N. Instead: (1) prompt for a
  CLEAN EMPTY DARK reserved band in the lower ~third ("no figure, no objects
  cross this band, flat negative space"); (2) draw the exact-N frame row + dates
  programmatically with PIL on that band.
- **Reserve the blank band explicitly in the prompt** and give the hero an
  explicit upper-two-thirds zone so nothing bleeds down into the overlay area.
- **Verify the reserved band is really empty BEFORE overlaying — programmatically,
  not with vision.** Convert to L, sample row-mean luminance down the band:
  rows ~≤5 (near-black, only grain) mean it is clear; a bright transition row
  (e.g. ~25) marks where the hero ends — start the frame row below it. Use plain
  PIL pixel loops (`im.load()`), NOT numpy — numpy can fail to import on
  thread-limited boxes (OpenBLAS pthread_create). Count bright pixels (>80) in
  the band: a handful (only grain/edges) = no text or objects crossing.
- **vision_analyze returns HTTP 451 (provider policy decline) on fine-art / figure
  posters even for generic layout questions** ("describe composition", "is the
  bottom third empty") when the frame contains artistic nudity/figure study — the
  blocking is on content, not on the question wording. Do NOT keep retrying or
  reword to dodge it (the 451 is final). Route around it: programmatic structure
  checks (band emptiness, palette via pixel stats) + deliver the image and let the
  HUMAN judge the hero/content. CometAPI vision may also return an empty completion
  for such frames — not a reliable QA substitute either.
- **Challenge a generated brief's literal hero before executing.** A calendar
  month numeral ("09") as the giant hero reads as a calendar notepad, not a
  poster, and carries no brand meaning ("69" the brand would; "09" the code
  doesn't). When the brief came from a concierge/LLM (not the owner), the hero
  concept is a hypothesis, not a mandate — research the actual venue/brand, and
  if the owner rejects the numeral, pivot the hero to the brand's real meaning
  (mood / body / the recognizable mark) instead of re-asking the model for a
  fancier numeral. Keep the two-layer date/program grid as the actual deliverable.

Support files:
- `references/event-poster-two-layer.md` — worked Studio 69 month-program poster:
  layout-grid + code-overlay pipeline, reserved-band programmatic verification,
  vision-451 routing, challenge-a-generated-brief's-hero lesson.

## Real-person key visual (brand face)

When the client wants THEIR face in the visual (e.g. Olga on arkkonabiuro.pl):
1. Curl the person's photo from the client site (`curl -sL https://site/hero.jpg -o /tmp/face.jpg`).
2. vision_analyze the photo into concrete prompt tokens: age, face shape, hair
   (color/length/part/volume), eyes (shape/color), brows, skin tone, nose, lips,
   expression, clothing, lighting.
3. Embed those tokens in the generation prompt + explicit «flattering» cues
   (accent hair volume, catchlights in eyes, smooth skin, soft jaw, defined
   cheekbones).
4. Verify likeness + strict brief compliance with vision_analyze on the output.

## Numbered contact sheet (grid) for human selection

When the deliverable is N candidates the user must CHOOSE from — faces, portraits, product shots,
sampled video frames — do NOT send N separate images and do NOT describe them in text. Compose ONE
numbered grid and let them answer with numbers («3, 7, 19»). This is a standing delivery format, not
a one-off; build it the same way every time. Full recipe: `references/numbered-contact-sheet.md`.

Non-negotiables:
- Every tile normalized to the same cell size via center-crop to the cell aspect, then `resize`.
- A contiguous number burned into each cell (black badge + `ImageDraw.text`); numbering runs 1..N
  ACROSS sheets, never restarts per sheet.
- Each sheet under ~250 KB so the platform renders it as a photo, not a document — 240x200 cells,
  5–6 columns, split at ~22 cells per sheet. Two readable sheets beat one unreadable mega-grid.
- Order tiles by the ranking that matters (score, duration, relevance) — the user reads top-left first.
- Deliver with `MEDIA:<abs path>` on its own line, followed by a compact key (number · one
  distinguishing fact) so the numbers are actionable without a second lookup.
- **State the real count.** If 44 were promised and 29 passed, send 29 and say why. Never pad a grid
  to hit a number, and never hold the message until a long discovery sweep completes — send what
  exists and keep working.
- **Deduplicate identities before composing** so the same subject never occupies two cells; a
  duplicate wastes a slot and erodes trust in the whole set.

Tile-selection rules (why grids come out empty or wrong):
- Pick the tile from a frame that actually DETECTS a face above threshold, not simply the first
  available still.
- Do NOT filter tiles on framing labels — 360p stills routinely read as «wide» while the face is
  perfectly usable. Accept on detection + clarity and RANK by framing instead of rejecting.
- Exclude known/blocklisted entities by normalizing punctuation before matching: raw substring tests
  miss dotted or hyphenated names (`Natasha.Teen`, `M1r4-J4nik`, `G-530`). Match on
  `re.sub(r'[^a-z0-9]+',' ', text.lower())` for both the candidate text and every exclusion name.
- Screen a separate list of widely-known names for the domain — an exclusion list of entities the
  user has personally interacted with will not contain them, and serving a famous name inside a
  «new candidates» sheet is the same failure as serving a repeat.

## Standing mode: a code-rendered CORE CARD on every reply (Indra's rule)

Every reply carries a visual of its **core message** — the one thing the reply is actually saying —
rendered by code. Structural replies add a full diagram ON TOP of the card.

- **Core card (v2, 2026-09-12):** `/opt/hermes/venv/bin/python3 /root/.hermes/scripts/render_core.py --kicker "<date · topic>" --status ok --core "<the one sentence>" --lines "<see syntax>" --foot "<next step>" -o /root/.hermes/media/cards/core-<ts>.png`
  — 1240 px, ~0.7 s, ~120 KB, `--check` prints the chromium path.
  **`--lines` mini-syntax** (pipe-separated, order preserved): `#LABEL` → small-caps section header ·
  `key :: value` → two-column row (muted label left, ink value right — the scannable workhorse) ·
  anything else → bullet. `**bold**` inside `--core`/values paints that token in the accent — use it
  on the ONE number that matters. `--status ok|warn|bad|info` prints a verdict chip top-right
  (`✓ РАБОТАЕТ` / `! ВНИМАНИЕ` / `✕ БЛОК`) — the whole point is that he reads the verdict in under a
  second. `--foot` carries the single next action.
- **THE CARD CARRIES THE PAYLOAD — THE PROSE IS A CAPTION (Indra, 2026-09-12).** He asked for
  *fewer tokens returned as text* and *better visualization of the core message*. So: put the
  answer, the numbers (as `key :: value` rows) and the verdict in the CARD, and keep the reply text
  to ~2–4 short lines — what the card cannot say (nuance, an honest caveat, the one question back).
  Do not restate the card's rows in prose; do not narrate the steps you took. Structure the card as
  verdict → evidence rows → next action, which is exactly the order he reads.
- **Card-first means: if the whole reply fits in the card, the reply text is one line.** A card that
  needs three paragraphs to explain it is a badly built card, not an argument for more prose.
- **NO EMOJI IN CARDS.** Nimbus Sans has no emoji glyphs, so `✅`/`⚠️`/`🔧` render as tofu boxes (empty
  squares) and look broken. Use the text glyphs the font actually has: `✓ ✕ · — → ≥ ≤ %`. Same reason
  `[x]` checklists don't render — use `•`.
- **The card must be the ONE message you are trying to get across in that reply** — not a summary
  of the actions taken, not a status list. If you cannot state it in one sentence, the reply has no
  core yet. (User's wording: «то сообщение, которое ты стремишься донести мне в респонсе».)
- **`<ts>` must include SECONDS** (`date +%Y%m%d-%H%M%S`). Minute precision collides when two
  cards render inside the same minute — the second silently OVERWRITES the first, so the file
  behind an already-sent `MEDIA:` link no longer matches the message it was sent with.
- **Verify the font is actually installed before claiming the design token is met.** The token asks
  for `Nimbus Sans`; when it is absent matplotlib only *warns* and silently falls back to DejaVu,
  so the delivered card quietly breaks the token. `fc-list | grep -i <font>` first, then pass a
  family you confirmed (or render via the chromium route, which has real font control).
- **Full diagram / sheet (structural replies only):** compose HTML in
  `/root/.hermes/media/diagrams/` and render with
  `render_diagram.py <in.html> <out.png> [--width N]`; embed matplotlib PNGs and hand-written SVG
  inline (base64 or `data:image/svg+xml`) so ONE chromium pass produces the whole sheet.
- **Render with code, never with an image model.** Diagrams carry exact labels, numbers
  and terms; flux/klein garbles typography and INVENTS plausible fake words
  (documented: «TerraCD», «Tomato», «Cloode»). Cost of a code render: **$0**.
- **Routes available:** ① HTML/CSS → chromium (typographic cards, panels — the workhorse)
  ② `matplotlib` (charts, baselines, trends) ③ hand-written SVG (flows, trees, architecture)
  ④ PIL (grids, contact sheets, and the trim pass both renderers use).
  **Still probe live before promising a route** (`/opt` is overlay; the venv is rebuilt at every
  deploy), but the armoury is no longer accidental — it is BAKED into the image. Since the
  visualization arsenal moved into the Dockerfile's `uv pip install` line (repo
  `indrad3v4/hermes-on-railway`) plus `apt-get install graphviz`, a clean redeploy now gives you:
  `matplotlib`, `seaborn`, `pandas`, `networkx`, `plotly`+`kaleido`, `altair`+`vl-convert`,
  `diagrams`, `graphviz`(+ the `dot` BINARY), `pydot`, `schemdraw`, `svgwrite`, `drawsvg`,
  `pygal`, `geopandas`, `folium`, `wordcloud`, `squarify`, `pywaffle`, `xlsxwriter`, `openpyxl`,
  `fpdf2`, `img2pdf`, `svglib`, `tabulate`, `prettytable`, `imageio` — alongside `PIL`,
  `numpy/scipy`, `scikit-learn`, `reportlab`, `qrcode`, `rich`, `pypdf`, `pymupdf`, `tesseract`,
  `chromium`, `ffmpeg`. Deliberately OUT because they are heavy GUI/compile stacks: `pycairo`,
  `pygraphviz`, `vtk`/`pyvista`/`open3d`/`mayavi`, `manim`.
  **Rule: to keep a route, add the package to the Dockerfile — `uv pip install` on the box is gone
  on the next deploy.** Still absent regardless of deploys: node/npx (so no drawio/DgrmJS), Java
  (no PlantUML), ImageMagick, LaTeX — cover that ground with the local mermaid/markmap/plotly
  bundles, graphviz `dot`, or the kroki route (below).
- **Design tokens that survive review (Indra's rules):** one accent colour (`#B4472E`), white
  background, `Nimbus Sans` (Helvetica metrics), 1240 px page width, no gradients, no stock icons,
  no decorative shadows. Kicker + H1 + one sub-line, then panels.
- **QA before delivering:** run `vision_analyze` on the PNG and ask «is all text legible and
  correctly spelled, any clipping/overlap/placeholder?». Code rendering makes garbling unlikely,
  not impossible — and the check catches CONTENT bugs too: a sheet titled «three routes» while
  four panels were shown was caught this way, and the wording fix costs seconds.
- **On a dense diagram, vision is NOT the proof — verify with size + OCR.** A busy mind map /
  multi-panel sheet can come back from `vision_analyze` described as an entirely different document
  (a Cyrillic 7-branch map was reported as a Chinese chart about medical disputes — full
  confabulation, no partial truth in it). For anything past a simple card: check the file size is
  in the expected range (a few-KB file is the empty-render smell), check `PIL` reports real
  dimensions, and OCR a crop — title plus 2–3 expected labels:
  ```bash
  /opt/hermes/venv/bin/python3 -c "from PIL import Image; im=Image.open('out.png'); print(im.size); \
    im.convert('L').crop((150,200,2400,3000)).resize((1125,1400)).save('/tmp/band.png')"
  tesseract /tmp/band.png - -l rus --psm 6 | grep -E "<expected label>|<another>"
  ```
  **Find the content before you crop it.** A hardcoded crop misses entirely on a 5600×6928
  markmap (the root sits mid-canvas, top-left is blank) and returns an empty OCR, which looks
  identical to an empty render. Locate the drawn area first, then crop a strip inside it:
  `bbox = ImageOps.invert(im.convert('L')).getbbox()` → crop `(x0, y0, x0+2400, y0+900)`.
  OCR the crop at NATIVE resolution, never the downscaled whole image — a 1400-px-wide version of
  a huge map OCRs to ~a dozen stray lines, a resolution artifact that reads as «empty file».
  Expected labels found = the render is what you built. A vision read that describes unrelated
  subject matter is a HALLUCINATION, not evidence of a bad render — never re-render, never
  reword the artifact, and never tell the user their map is wrong because of it.
- **Deliver** with `MEDIA:<abs path>` on its own line, same as any other visual.

### Three more code routes found by GitHub scan (installed + proven 2026-09-11)

All run through the SAME chromium, using JS bundles cached in `~/.hermes/assets/viz/`
(no CDN at render time, no node, no npm, no apt). Driver: `~/.hermes/scripts/viz_render.py`.

| Route | Command | Use for |
|---|---|---|
| **mermaid** 11 | `viz_render.py mermaid <code.mmd\|-> out.png` | flowcharts, trees, sequence, gantt — Cyrillic renders exactly |
| **markmap** 0.18 | `viz_render.py markmap <file.md\|-> out.png` | mind maps from markdown (Buzan's own instrument) |
| **plotly** 7.0 | `viz_render.py plotly-html <file.html> out.png` | charts with exact numeric labels; inline `plotly.min.js` for offline renders |

- **PICK THE ROUTE BY NODE COUNT — mermaid chokes on big graphs, markmap does not (verified 2026-09-11).**
  The same 108-node tree rendered by mermaid «succeeded» (338 KB PNG) but laid the whole graph out as
  ONE narrow vertical column: `PIL` size 6400×2800 with the content bbox only ~840 px wide, running to
  the bottom edge = the graph was clipped and unreadable, while the file size and exit status both
  looked healthy. markmap rendered the same data as a clean horizontal tree (4800×5020, every top-level
  branch OCR-verified). Rule: mermaid for ≤~30 nodes (flows, sequences); markmap for anything that
  grows branch-by-branch (a whole book/board). Detect the failure with the bbox check, not with the
  success message: if `invert(im).getbbox()` is a narrow column, or its far edge equals the canvas
  edge, the layout did not fit — switch renderer, do not just enlarge the canvas.
- **PICK THE ROUTE BY DATA SHAPE, not only by node count.** For 8–15 nodes that EACH carry several
  labelled fields (a stage sheet: per step — canon pages, sources/confidence, card id, one-line
  market read, gap), the deliverable is an HTML/CSS PANEL SHEET (2-column grid, one panel per node)
  rendered through `render_diagram.py` — not a markmap. The same data as a markmap came out 4400×4948
  of pure branch text with the readings scattered across the canvas; the panel sheet (3360×4046) put
  every node's numbers in a fixed place and survived OCR verification. markmap stays the right call
  for pure hierarchy (nothing but parent→child names); switch to panels the moment each node has
  comparable attributes. Keep the sheet's content generated from the DATA FILE (the research/matrix
  `.txt`), never hand-typed into the HTML — otherwise a re-run of the data pipeline silently leaves
  the sheet describing last week's numbers.
- **Strip markdown emphasis from source text before it reaches the sheet.** Research/digest files
  carry `*`/`**` emphasis and stray footnote markers from the pipeline that produced them; escaped
  into HTML they render as literal asterisks mid-sentence (`…«duży» 1 92 **`) and read as a broken
  render. Run `re.sub(r"\*{1,3}", "", text)` on every escaped cell.
- **An odd node count leaves the last grid cell empty — that is layout, not missing content.** Say
  the sheet is complete by count (`N of N panels`) instead of re-flowing the grid to hide the hole.
- **Chromium flags that make or break these:** `--allow-file-access-from-files` (else local
  `<script src="file://…">` is blocked) and `--virtual-time-budget=6000` (lets the JS finish
  before the shot).
- **markmap: use explicit init, NOT the autoloader.** The autoloader animates the layout and the
  screenshot fires first — output is a single text fragment (8 KB). Correct pattern: load
  `d3` + `markmap-view` + `markmap-lib` (iife) and call
  `Markmap.create(svg, {duration: 0, autoFit: true}, root)` after `Transformer().transform(md)`.
- **markmap renders emoji as empty boxes (tofu).** `⛔` and `⚠` inside node text come out as `▢`,
  which reads as a rendering bug in the delivered image. Use plain text markers instead
  (`ПРАБЕЛ:`, `УВАГА:` / `GAP:`, `NOTE:`) — same signal, no glyph risk. Cyrillic itself renders
  exactly; it is only the symbol range that fails.
- **plotly: never rely on `include_plotlyjs="cdn"`** — inline the local bundle so a render works
  with no network.
- **Rejected on facts (do not retry without new evidence):** `mingrammer/diagrams` needs the
  graphviz `dot` binary (no apt here), PlantUML needs Java (absent), and every node/npm renderer
  (drawio, DgrmJS, flowchart-fun) is dead without node.
- **QA depends on density; file SIZE is the first smell either way.** A 8 KB PNG that «succeeded» was an empty markmap — check size and `PIL` dimensions before anything else. For a simple card, `vision_analyze` is the QA. For a dense diagram (mind map, multi-panel sheet), vision is NOT the proof — it confabulates whole documents (see the dense-diagram rule above); verify with size + dimensions + an OCR crop of the located content bbox.

### Kroki — 20+ diagram languages over HTTP, no binaries (found via /firebrowsing 2026-09-11)

This reverses the earlier «rejected on facts» verdicts. `graphviz`, `PlantUML` and `D2` needed
binaries this box does not have (no apt, no Java) — but **kroki.io renders them over HTTP**.
Verified live: graphviz ✓ 3121 B SVG · plantuml ✓ 5006 B · d2 ✓ 11305 B · mermaid ✓ 13162 B
PNG after rasterizing.

```bash
viz_render.py kroki input.d2   out.png --type d2
viz_render.py kroki input.puml out.png --type plantuml
viz_render.py kroki input.dot  out.png --type graphviz
```

- Types include `graphviz`, `d2`, `plantuml`, `mermaid`, `nomnoml`, `svgbob`, `wavedrom`,
  `structurizr` — pass the name as `--type`.
- **kroki.io answers 403 to the default Python `urllib` User-Agent** while `curl` works. Send a
  real UA or you will misread it as «blocked» (cost me one wrong conclusion).
- It is a **third-party HTTP service**: the diagram source leaves the box. Fine for structure
  and shapes; keep client-confidential content on the local routes (mermaid/markmap bundles,
  matplotlib, SVG, chromium).
- Fills exactly the gap left by the missing binaries: architecture, sequence, state machines,
  ER models, C4 — with nothing installed.

## Pitfalls

- **`render_core.py` has no default output path — `-o` is MANDATORY and must survive the shell.**
  Omit it and the script dies with `TypeError: expected str, bytes or os.PathLike object, not
  NoneType` from `os.path.abspath(None)` — a message that reads like a code bug, not a missing
  argument. Two traps in practice: (a) writing the command across multiple lines with `\`
  continuations, where the shell can drop the `-o` token (symptom: `/usr/bin/bash: line N: -o:
  command not found`); (b) passing `--kicker/--core/--lines` and stopping there. Put all four
  flags on ONE line with `-o /root/.hermes/media/cards/core-$(date +%Y%m%d-%H%M%S).png` last, and
  confirm the printed `CORE CARD: <path> <bytes>` line before referencing the file in a reply.
- **NON-LATIN CARD TEXT: pass the arguments through Python, not through a shell heredoc.** Cyrillic
  (and any non-ASCII) sent through `bash <<'EOF'` / multi-line `\`-continued commands can arrive
  mangled — the render succeeds, the PNG looks clean, and the corruption shows up only as
  replacement diamonds inside a word («Ш��гі»). Two defences, both cheap: (a) build the card by
  calling the renderer with an argument LIST (`subprocess.run([...])` from `execute_code`, one
  element per flag/value, no shell parsing at all); (b) when a card contains non-Latin text, ask
  `vision_analyze` explicitly whether every glyph rendered correctly — the generic «any clipping or
  placeholder?» question returns a summary that reads fine while a broken word sits in the middle.
  Note the failure is silent in the exit code AND in the file size.
- **A diagram past ~50 nodes cannot be delivered as a photo — send the SOURCE file with it.**
  Telegram downscales a sent image to roughly 1280 px on the long edge, so a 4000+ px mind map
  (a whole book's structure, 80+ nodes) arrives unreadable, and a busy 2200 px sheet loses its small
  labels too. The fix is not a smaller diagram — it is a second artifact: render the PNG for the
  visual impression AND deliver the machine-readable source (`.md`/`.txt` of the same tree) with
  `MEDIA:`, then attach that source to the relevant kanban card (`kanban attach <id> <file>`) so it
  survives the chat. State plainly which one is the working document.
- **Chromium fails SILENTLY when the output directory does not exist** — no error, no file, and a
  stderr-suppressed wrapper reports success. `os.makedirs(os.path.dirname(out), exist_ok=True)`
  before every render, and treat a missing PNG as the failure signal.
- **A diagram/tree produced by a builder script must be edited in the SCRIPT, not in its
  output.** Where the pipeline is `build_*.py` → emitted `.md`/`.mmd` → rendered PNG, a patch
  to the emitted file looks successful and is silently reverted the next time the generator
  runs — no error, your nodes just vanish. Find the source of truth first (`grep` the node text
  inside the generator) and add the node to the generator's data structure. Two traps that cost
  time here: an f-string referencing a constant that does not exist in the generator kills the
  WHOLE rebuild with `NameError` and writes no file at all (the map then looks «not rebuilt»,
  not «broken»), and re-running the generator after a manual edit yields a fresh file with the
  edit gone — always re-open the artifact after a rebuild instead of assuming the change survived.
- Describing an image instead of sending it = the #1 trust-killer in delivery.
- Trusting the generator's URL without downloading: verify local bytes
  (`head -c 8 file | od -c` → `\211 P N G`) before MEDIA:.
- Text rendered by the model itself (especially non-Latin) garbles — always
  overlay programmatically, never ask the model to render sentences.
