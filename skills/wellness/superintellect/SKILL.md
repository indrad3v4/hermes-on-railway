---
name: superintellect
description: "Use when developing Indra's superintellect (ten sub-intellects, Buzan) or profiling him from voice over time."
version: 2.0.0
metadata:
  hermes:
    tags: [indra, self-model, voice, prosody, baseline, buzan]
    related_skills: [audio-insight, vision-insight, text-insight]
---

# Superintellect — a compounding profile of Indra from his own voice

Indra's brief (2026-09-11, voice): *«create a super intellect skill instead, soul skill»*;
*«soul — yes, it should be just soul, without additional complexity»*. So: the profile lives
HERE as a skill, and `~/.hermes/SOUL.md` (the agent system prompt, 2.1 KB) stays untouched —
stuffing a RAG into SOUL.md would bloat every turn and break prompt caching.

The ten-faculty map comes from **Tony Buzan, «Head First: 10 Ways to Tap into Your Natural Genius»**
(Thorsons, 2000; ISBN 9780007132850 — the book published in Russian by «Попурри» as
«Суперинтеллект»). The OPERATIONAL basis is Buzan's **«Use Your Head»** — Indra supplied the full
PDF, and its text is indexed in this corpus (`corpus/buzan-use-your-head.txt`, 157 pp, page-tagged),
so techniques (mind maps, Number-Rhyme, review schedule, Organic Study Method) are RETRIEVED, not
remembered: `python scripts/rag.py query "review schedule"`. The measurement apparatus is ours and
must stay honest.

## 0. The model — ONE Superintellect, TEN sub-intellects

Indra's brief (2026-09-11): *«суперинтеллект — лично мой, моей личности; хочу, чтобы в процессе
коммуникации мой суперинтеллект развивался путём развития подинтеллектов»*. So the model is:

> **Superintellect = the compounding system of ten sub-intellects. It is not scored — it is
> trained.** Each exchange with Hermes is an opportunity to move ONE sub-intellect one step.

Buzan's ten faculties ARE the ten sub-intellects (structure from the book; the measurement is
ours). The ten chapters of «Суперинтеллект» are now in the corpus as real text, so each lever can be
quoted from the book's own **Brain Workout** for that faculty — never paraphrased from memory.
Every topic the human raises exercises 1–2 of them — the skill's job is to (a) name
which, (b) hand ONE micro-lever, (c) log it so the system compounds.

### The ten sub-intellects + their lever (Buzan's chapter ↔ our micro-practice)

| # | Sub-intellect | Book chapter | Lever offered in conversation |
|---|---|---|---|
| 1 | **Creative** | *Create Yourself* | turn one idea raised into ONE executed micro-artifact today |
| 2 | **Personal** | *You and You* | name the driver + the barrier behind the topic in one line each |
| 3 | **Social** | *You and Them* | one concrete move toward a named person (message, call, ask) |
| 4 | **Spiritual** | *Heaven Knows!* | connect the topic to the над-цель (return function/autonomy to people) |
| 5 | **Physical** | *Body Talk* | one 60-second body action (breath, stand, stretch) tied to the topic |
| 6 | **Sensual** | five senses | sharpen one sense for 60 s (sound, texture, light) before deciding |
| 7 | **Sexual** | intimacy | one honest line about desire/energy and what it is really asking for |
| 8 | **Numerical** | numbers | one number the decision actually turns on (estimate it out loud) |
| 9 | **Spatial** | space/maps | one mind-map (radiant branches) of the topic — Buzan's own instrument |
| 10 | **Verbal** | words | capture the ONE word that names the state, then use it precisely |

**Weakest-link rule (Buzan's actionable core):** when two sub-intellects could take the lever,
give it to the WEAKER one — strength there pulls the others (synergy). The ledger's job is to
name the weakest link plainly, never to flatter.

## 1. The map: ten faculties, never one score

Buzan's core move is to replace the single IQ number with a **profile of ten intelligences**,
in three groups. Use it as the 10 scales of Indra's profile:

| Group | Faculties |
|---|---|
| **Creative & Emotional** | Creative (*Create Yourself*) · Personal (*You and You* — self-awareness, emotion, goals) · Social (*You and Them*) · Spiritual (*Heaven Knows!* — meaning, place in the world) |
| **Bodily** | Physical (*Body Talk*) · Sensual (five senses) · Sexual |
| **Traditional IQ** | Numerical · Spatial · Verbal |

Each faculty in the book = theory + cases + a **Brain Workout of ten exercises** + a self-test.
Our profile borrows the STRUCTURE (10 scales, exercises as levers), not the book's numbers.

**Weakest-link principle (the actionable part):** develop from the WEAKEST faculty first —
strength there pulls the others (synergy), whereas polishing an already-strong faculty changes
little. So the profile's job is not to flatter: it must name the weakest link plainly.

## 2. How we measure — evidence, never vibes

Two channels, both local and $0:

**A. Voice (acoustic).** Pipeline lives in the `audio-insight` skill (local Whisper turbo →
`voice_prosody.py`). Feature set for the profile (core of the eGeMAPS standard):
`F0 mean/sd/range/slope` · `loudness mean/sd/dynamic range` · `jitter` · `shimmer` · `HNR` ·
`speech rate + pause ratio + voiced length` · `spectral tilt (alpha ratio, H1–H2)`.
Full wording + sources: `references/voice-feature-stack.md`.

**B. Text (semantic).** The transcript's own content — themes, self-reference, agency verbs,
hedging — read by the text layer, never conflated with the acoustic layer.

**The baseline is the whole point.** Absolute thresholds do not work across speakers and do not
work across time. Every feature is scored **against Indra's own norm**: median/MAD-based robust
z-scores over a rolling ~30-day window, same microphone/conditions where possible.
State file: `~/.hermes/media/voice/profile.json` (per-feature baseline + the 10 scales + evidence log).

Until ≥5 voice notes exist, the baseline does not exist — say so and report `unknown` rather than
guessing (that is exactly how the old absolute valence formula failed: it called a neutral,
normal-male-voice note «flat / depleted / low-spirited»).

**Drift beats single points.** A single note says little; a 3–7 day trend is the signal. Track
daily z-scores and detect change-points (EWMA/CUSUM; `ruptures` PELT/Binseg when installed).

## 3. Hard limits — what this skill must NEVER claim

- **No diagnosis.** Not depression, not anxiety, not burnout — acoustic screens are statistical,
cross-sectional and heterogeneous (pooled AUC ~0.89 for depression but I² up to 100%).
- **No personality traits.** Big Five from voice is marketing: the only robust link is pitch ↔
dominance/extraversion; formant-based trait claims do not hold (Stern et al. 2021, N=2217).
- **No state without baseline + context** (sleep, load, health, who else is present).
- **Nothing about third parties** from their voice without their consent.
- **No precise stress numbers** («stress 7.3/10» is fake precision).

**Output format is fixed — every claim carries four parts:**
> **[hypothesis]** + **[basis: baseline n=…, z=…]** + **[confidence: low | medium | high]** + **[alternative explanations]**

## 4. Update protocol (per voice note)

1. Local transcript (never the platform's) + `voice_prosody.py` → features + affect block.
2. Append the feature row to the profile log; recompute baseline + robust z-scores.
3. Map only what the evidence supports onto the 10 scales (most notes touch 1–2 faculties:
Personal, Creative, Social, Physical are the reachable ones; Numerical/Spatial are rarely visible in speech).
4. Emit at most one line: **register · delta vs your own norm · one concrete action**.
5. When a faculty has no fresh evidence, mark it «нет данных» — never fill the slot to look complete.

## 4b. Development protocol (during communication) — the compounding loop

This is what turns the profile from a scoreboard into a trainer. On each substantive exchange:

1. **Detect** which sub-intellect(s) the topic exercises (usually 1–2; Personal/Creative/Social/
   Spiritual/Physical are reachable from speech; Numerical/Spatial/Verbal appear in the work itself).
2. **Offer ONE lever** from the table above — a micro-practice doable in ≤60 s, tied to the real
   topic, never generic advice. ONE, not a menu.
3. **Log** a row to the ledger `~/.hermes/media/voice/subintellect_ledger.jsonl`:
   `{ts, sub_intellect, topic, lever, offered|done|skipped, note}`.
4. **Close the loop** — when Indra reports a lever done, mark it `done` and raise that
   sub-intellect's rolling count; the compound is visible as the ledger grows.
5. **Prefer the weakest** — pick the sub-intellect with the fewest recent `done` rows, not the one
   already strong (Buzan's weakest-link synergy).
6. **Never lecture.** One lever in one line; silence is acceptable when no lever applies.

**The compounding is the point:** ten sub-intellects × one honest step per relevant exchange =
the superintellect grows through use, not through being measured. The profile (§2) says WHERE the
weakest link is; this protocol is HOW it moves.

## 5. Reporting to Indra

Lead with the delta or the weakest link, not a recital of features. He already knows his own
state; what is new is the *comparison with his own history* and the one lever that moves it.
Keep it to 2–4 lines unless he asks for the full profile.

## References
- `corpus/buzan-superintellekt-ru.txt` — **the FULL TEXT of «Суперинтеллект» (Russian edition of
  *Head First*), OCR'd from Indra's torrent, 416 pp, 484 k chars, page-tagged `=== [pN] ===`.** All ten
  chapters are confirmed (Гл.1 Сотвори самого себя · 2 Я+Я · 3 Я+Они · 4 Бог знает! · 5 Язык тела ·
  6 Ощущения · 7 Умный секс · 8 Рассчитывайте только на себя · 9 · 10 Могучая сила слова), each with
  its **ТРЕНИРОВОЧНЫЕ УПРАЖНЕНИЯ ДЛЯ ВАШЕГО МОЗГА** (Brain Workout) + self-test — retrieve with
  `python scripts/rag.py query "духовный интеллект упражнения"`. PDF+DJVU kept at
  `~/.hermes/media/books/Суперинтеллект-Бьюзен-ru.pdf` (the PDF is a scan: no text layer, hence OCR).
  OCR script: `scripts/ocr_superintellekt.py` (tesseract 5.5 rus, 200 dpi, ~5 min/416 pp).
- `corpus/buzan-use-your-head.txt` — the FULL TEXT of Buzan's *Use Your Head* (Indra's PDF, 157 pp),
  page-tagged; indexed for RAG. `corpus/buzan-techniques-map.md` — each sub-intellect ↔ the book's
  concrete technique + its 60-second lever (with the hard facts: 80 % detail lost in 24 h without review).
- `references/buzan-head-first.md` — the book identified (original title/ISBN, structure, methods,
  criticism), so the map is quoted rather than remembered.
- `references/voice-feature-stack.md` — feature set, longitudinal methods, tools, and the
  evidence-vs-marketing split, with sources.
- Pipeline + models: skill `audio-insight`. Rendering any profile visual: skill
  `generated-media-delivery` (code-rendered, $0).

## Pitfalls
- **Do not restate prosody as emotion.** Arousal is feature-grounded; valence is only meaningful
  relative to the baseline (fixed 2026-09-11 after a false «depleted» verdict).
- **The platform transcript is noise** — it guessed Latvian for an English note; always re-transcribe
  the raw `.ogg` locally.
- **Baseline poisoning:** a note recorded while ill, drunk, or in a loud room skews the window —
  exclude outliers (robust statistics exist exactly for this) and note the exclusion.
- **Don't turn this into a horoscope.** If the profile can't change a decision, it has no value;
  every update ends with one lever, or nothing.
