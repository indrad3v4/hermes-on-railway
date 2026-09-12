# Worked example: Studio 69 month-program poster (two-layer pipeline)

Class worked case (2026-09-09) proving the two-layer event-poster pattern in
`generated-media-delivery`. Venue: Studio 69 (Krakow, Starowislna 89) — a bold,
body-positive sensual art/play studio, per the TRES BIENSKI lineage
(«We bring seduction to the dancefloor», «wear your bravest outfit … we expect
drama», RA/happeningnext/krajownik). Owner voice-ratings: tone = «Смелая»
(bold), «creative nudity is ok» (fine-art figure allowed, never pornographic).

## The brief trap
Original brief (written by a concierge/LLM, not the owner) demanded a giant
sculptural "09" month-numeral hero. Owner rejected it hard («why 09?????»).
Root cause: a month code has no brand meaning — it reads as a calendar notepad.
The hero must carry the brand (its mark or its mood), not the calendar number.
Lesson encoded in SKILL.md: challenge a generated brief's hero before generating.

## What worked (final pipeline)
1. RESEARCH the venue/brand first (web_search + browser): identity, audience,
   tone — never generate a brand poster off a style-only brief.
2. PROMPT the model for a CLEAN canvas: hero in upper two-thirds, and an
   EXPLICIT empty dark reserved band in the lower ~35% («no figure, no curtain,
   no objects cross this band»). Portraits 4:3 via fal klein/9b (~$0.01).
   `No text / no letters / no numerals / no watermark` always on.
3. VERIFY the reserved band programmatically (no vision): PIL L-channel row-mean
   luminance + bright-pixel count. Real numbers: band 71%+ luminance ~2-3 (near
   black, grain only); 65-71% transition row ~26 (hero ends here → start frames
   below); bright(>80) px = 475 sampled ≈ only grain/edges. ⇒ band clean.
4. DELIVER the canvas via MEDIA: and let the OWNER judge the hero/content —
   vision is blocked (451) on figure content and is not a QA substitute for it.
5. LAYER the exact-6 date/program frames + text with PIL onto the verified band
   (model cannot count to 6 — see SKILL.md).

## Vision-block note
vision_analyze returned HTTP 451 on this fine-art figure frame for even generic
layout questions. Not recoverable by rewording. CometAPI vision returned an
empty completion. Only programmatic structure checks + human judgment survived.
