# Task — Deep-research improvement plan for the `/firebrowsing` Hermes skill

## Goal
Produce a concrete, evidence-backed plan to upgrade the `/firebrowsing` skill so it behaves more like a real *Perplexity-Deep-Research* loop by default: broader discovery, source-comparison, claim grounding, failure recovery, structured outputs, and a reusable research template — while still using only the resources Hermes already has (CDP browser, Firecrawl MCP, free-tier web search, and any optional API keys the user already holds).

## Hard rules
- Ground every recommendation in the real skill and real tools as they exist in this Hermes installation, not in generic marketing copy.
- Do not invent commands, APIs, or config keys. If something is not verifiable from the live docs or repo, say so explicitly and mark it as unverified.
- Prefer changes that are testable inside `browser_exec` / CDP and Firecrawl MCP, because that is the default local path.
- Keep cost in mind: Perplexity-style depth is only useful if it does not silently blow up token/credit spend. Suggest thresholds, stop conditions, and a lightweight default path.

## What to research and compare
1. Read the current `/firebrowsing` skill end-to-end: its decisions, paths, helpers, output contract, pitfalls, and missing pieces.
2. Read the relevant Hermes docs and reference files that touch this skill: browser/CDP behavior, Firecrawl MCP, web search backends, skill authoring conventions, and any "research" or "deep research" guidance Hermes already documents.
3. Identify the gap between today's `/firebrowsing` and what people mean when they say "Perplexity-style deep research": multi-source cross-checking; follow-up querying; explicit confirmed/inferred/disputed treatment; retrieval for JS-heavy/bot-walled/paywalled sites; structured outputs; pacing and retry logic.
4. Look for real failure modes people hit with browser-based scraping / Firecrawl local vs API, and what mitigations are viable in Hermes (CDP selectors, waits, forms, scroll, clicks, alternate URLs, sitemap/robots/alternate paths, local fallback).
5. If there are known Hermes docs, issues, or community notes about better research workflows, use them; otherwise say the evidence was thin.

## Output format
Return a structured plan with diagnosis, default behavior, concrete skill changes, a reusable research template, validation/guardrails, and unknowns/risks.

## Tone and detail
Write for the person who maintains this skill and wants to ship a better default without breaking the no-key local path. Be specific and actionable without generic AI-research advice.

## Constraints from the environment
- Primary local extraction path: browser_exec + CDP.
- Firecrawl MCP is an optional cloud path.
- Web search may be limited by tier; multi-source discovery must not assume unlimited credits.
- Skill remains usable without extra API keys unless a specific improvement genuinely needs one.
