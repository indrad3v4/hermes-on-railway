# Voice feature stack + longitudinal methods

Distilled from `~/.hermes/dvizhok/research/voice-longitudinal-model.md` (2026-09-11, ~40 sources).

## What is actually provable from voice

| Signal | Status |
|---|---|
| **Arousal / activation** | RELIABLE — F0, loudness, speech rate move together |
| **Acute stress** | MEDIUM — meta-analyses show F0 rise, but publication bias is present |
| **Valence** | only with TEXT alongside — acoustics alone do not carry it |
| **Depression** | statistically screenable (pooled AUC ~0.89) but cross-sectional, I² up to 100 %, mostly English data — a screen, never a diagnosis |
| **Fatigue / sleep debt, anxiety** | weak / indirect |
| **Emotion regulation** | only dynamical — reactivity and recovery, needs repeated samples |
| **Big Five personality** | MARKETING — the only robust link is pitch ↔ dominance/extraversion; formant-based trait claims do not replicate (Stern et al. 2021, N=2217) |

## Minimal interpretable feature set (core of eGeMAPS)

1. **F0** — mean, sd, range, slope
2. **Loudness** — mean, sd, dynamic range
3. **Jitter** (local)
4. **Shimmer** (local)
5. **HNR** — harmonics-to-noise ratio
6. **Timing** — speech rate, pause ratio, voiced/unvoiced lengths
7. **Spectral tilt** — alpha ratio, H1–H2

MFCC 1–4 only as input to a model, never as an interpretation. Full eGeMAPS (88 features) is one
`openSMILE` call. None of jitter/shimmer/HNR means anything in isolation — only the *ratio* versus
one's own history.

## Longitudinal methods that work

1. **Personal baseline + robust z-scores** — median/MAD (not mean/sd) per feature, rolling ~30-day
   window, fixed conditions (same mic, comparable speech).
2. **Drift / deviation detection** — EWMA and CUSUM over daily z-scores; change-point search with
   `ruptures` (PELT/Binseg). A 3–7 day trend outweighs any single note.
3. **Voice diary / EMA** — 3–4 recordings a day plus a 1–7 self-report of valence/arousal and
   context (sleep, load). Precedents: bipolar-disorder monitoring over 6–12 months; per-individual
   EMA + causal modelling; participant-facing acoustic EMA apps.

## Tools that run locally on CPU

Already installed: `librosa`, `numpy`, `scipy`, `soundfile`, `scikit-learn`.
Worth adding: `opensmile`, `praat-parselmouth`, `pyloudnorm`, `pandas`, `matplotlib`, `ruptures`.
Optional: `disvoice`; `faster-whisper` for the text layer.
Audio-LLMs (Qwen2-Audio, SALMONN) are slow on CPU and lean on LEXICON rather than acoustics —
not a measuring instrument.

## Why the baseline is non-negotiable

Absolute thresholds assume a speaker. Concrete failure: the original `voice_prosody.py` valence
formula (`0.5 + (f0-160)/160 + (centroid-1800)/2500`) gave **`valence 0.0 / negative / flat,
depleted, low-spirited`** for Indra on a *neutral* message, because his median F0 is 88.8 Hz —
a normal male voice — and the formula was tuned for a much higher pitch. A fixed formula produced
a fixed, wrong verdict every time. Fixed 2026-09-11: valence is now computed only as a z-score
against the personal baseline; with no baseline it returns `unknown`.

## What must never be claimed

- Diagnosis of any condition.
- Personality traits from voice.
- State without baseline AND context.
- Anything about third parties without their consent.
- Precise stress numbers.

**Fixed output form:** [hypothesis] + [basis: baseline n, z] + [confidence] + [alternative explanations].
