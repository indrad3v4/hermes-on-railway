---
name: firebrowsing
description: >
  Local-first, zero-cost web research and extraction using Hermes's CDP browser.
  Escalates to multi-source deep research for fuzzy/comparative questions.
  Optional paid Firecrawl fallback only if the user has explicitly configured a key.
version: 2.0.0
author: Indradeva, Hermes Agent
license: MIT
metadata:
  version: 2.0.0
  hermes:
    tags: [web, scraping, browser, firecrawl, deep-research]
---

# /firebrowsing

Local Firecrawl-style extraction via `browser_exec` + CDP, with an optional deep-research
mode for comparative/fuzzy questions. No API key required for core extraction. Optional
Firecrawl API key adds a cost-bearing fallback only when local extraction is exhausted.

## Cost policy (hard constraint)

- **Default and "deep" modes are $0** — local CDP + local/self-hosted search only.
- Firecrawl API is **OPTIONAL, OFF by default**, and only invoked if:
  - `FIRECRAWL_API_KEY` is set,
  - local extraction has exhausted all retries, AND
  - the user has not disabled it.
- Never print or log the Firecrawl key.
- Every deep-research run is bounded by explicit fetch/time budgets (see below).

## Paths

### 1. LOCAL (default, free)
Use `browser_exec` with the pre-imported harness globals:
`new_tab`, `goto_url`, `wait_for_load`, `wait_for_element`, `js`,
`click_at_xy`, `scroll`, `fill_input`, `type_text`, `press_key`, `capture_screenshot`.

Load helpers via:

```python
import sys
sys.path.insert(0, '/root/.hermes/scripts')
with open('/root/.hermes/scripts/browser_helpers.py') as f:
    exec(f.read(), globals())
```

Core helpers (unchanged from the existing skill):

- `scrape_url(url, formats=["markdown"])` → `{url, metadata, markdown?, html?, screenshot?}`
- `extract_markdown()` → clean markdown with nav/footer/ads removed
- `extract_metadata()` → `{title, description, canonical, robots}`
- `extract_structured(schema)` → `{field: value}` by CSS selector map
- `search_duckduckgo(query, limit)` → list of `{title, url, description}`
- `map_site(url, limit)` → list of same-origin URLs
- `crawl_site(url, limit)` → list of `{url, metadata, markdown}`

### 2. SEARCH backends
- **Default:** DuckDuckGo HTML extraction via `search_duckduckgo()`, **with automatic
  fallback to Bing HTML** (`search_bing()`) when DDG serves a bot-captcha.
  `search_duckduckgo()` also falls back to Bing on DDG exceptions.
- **Optional zero-cost upgrade:** if `SEARXNG_URL` env var is set, use a self-hosted
  SearXNG JSON endpoint as the search backend. This is still $0 in API fees but requires
  the user to run its own instance. When set, SearXNG takes priority over DDG/Bing.
- If a backend returns 0 results (no captcha), apply **query reformulation** before giving up — never an infinite search loop.

### 3. FIRECRAWL (optional, cost-bearing)
- Only reachable through the `escalate_to_firecrawl()` guard.
- Never called implicitly from the default or deep-research flow.
- If used, log that it was used (without the key) so the user can see cost-bearing calls.

## Trigger: Deep Research Mode

Activates when the user question contains comparison/recommendation language, is explicitly open-ended/research-oriented, or the user passes `deep` as a mode hint. Otherwise use the existing single-page extraction path.

## Budgets (hard caps, no exceptions)

| Mode | breadth (queries) | depth (follow-up rounds) | max_sources | max_fetch_time |
|---|---:|---:|---:|---:|
| quick/factual | 1 | 0 | 1 | 20s |
| standard | 3 | 1 | 5 | 60s |
| deep | 5 | 2 | 8 | 180s |

- `breadth` = number of distinct search queries to issue.
- `depth` = number of recursion rounds when gaps remain.
- `max_sources` = total distinct URLs fetched across all queries.
- `max_fetch_time` = wall-clock budget for fetching (not counting synthesis).

Hard stop: never fetch beyond `max_sources`, and stop when the budget is hit or acceptance criteria are met.

## Step sequence

1. **PLAN** — generate `breadth` distinct search queries: synonyms, sub-entities, and angle splits.
2. **SEARCH** — run each query via the active search backend. Dedupe candidate URLs by normalized host + path.
3. **FETCH** — for each candidate (up to `max_sources`), call `resilient_scrape()` (local CDP only, unless escalated).
4. **VALIDATE** — accept a scrape only if markdown length > 200 chars and selector-based target-content validation succeeds.
5. **FOLLOW-UP (if depth > 0)** — if a sub-question still has zero valid sources, generate targeted follow-up queries and repeat once, decrementing `depth`.
6. **SYNTHESIZE** — extract claims per source and compare across sources.
7. **LABEL confidence** — `confirmed`, `single_source`, `inferred`, or `disputed`.
8. **STOP** — the moment budget is hit or acceptance criteria are met.

## resilient_scrape() — local-only retry chain

```text
def resilient_scrape(url, max_attempts=2):
    for attempt in range(max_attempts):
        r = local_cdp_scrape(url, wait_for_element_timeout=5 + attempt * 5)
        if r.get('markdown') and len(r['markdown']) > 200:
            return {**r, 'source': 'local_cdp'}
        time.sleep(1.5 ** attempt)

    if is_bot_wall_or_paywall(r):
        return {'error': 'blocked', 'url': url, 'classification': classify_failure(r)}

    if FIRECRAWL_API_KEY and firecrawl_enabled_by_user:
        return escalate_to_firecrawl(url)

    return {'error': 'extraction_failed', 'url': url}
```

- Retries only via local CDP wait/backoff.
- Never silently escalates to a paid call.
- Bot-wall/paywall classification is advisory, not guaranteed.

## Output contract (superset — old fields unchanged)

```json
{
  "ok": true,
  "source": "local_cdp",
  "title": "Research: <query or page title>",
  "url": "<primary url or null>",
  "markdown_len": 4210,
  "snippet": "...",
  "sources": [{"url": "...", "title": "...", "source": "local_cdp", "markdown_len": 4210}],
  "summary": "synthesized answer",
  "findings": [{"claim": "...", "confidence": "confirmed|single_source|inferred|disputed", "sources": ["url1", "url2"], "quote": "..."}],
  "open_questions": ["..."],
  "next_queries": ["..."],
  "confidence": "medium",
  "cost": "0.00",
  "error": null
}
```

- `sources[]` is always present in deep-research mode; in single-page mode it may contain just one URL.
- `cost` is human-readable; local-only runs use `"0.00"`.
- `error` is non-null only when the run failed entirely.

## Guardrails

- **No API cost by default or in deep mode** — Firecrawl is not called unless the key is set AND the user opted in.
- **Max 2 depth levels**, **max 8 sources (deep)**, **max 5 sources (standard)** — hard stop.
- **~50KB total scraped content cap** per research run.
- **Every claim requires a source URL** — no claim without a citation.
- If SearXNG is not configured, degrade to DDG→Bing with query-reformulation retry — never an infinite loop.
- If local extraction fails on all candidates and Firecrawl is unavailable, return typed `blocked` / `extraction_failed` errors rather than fabricating content.

## Test cases

1. `"best self-hosted AI agent frameworks 2026"` — expect 3+ sources, confidence labels, `$0.00` cost, no Firecrawl calls.
2. `"capital of France"` — expect single fetch, no deep-research loop.
3. Known bot-walled URL with no `FIRECRAWL_API_KEY` — expect typed `blocked` error, zero crashes, zero paid calls.

## Implementation notes

- The deep-research orchestration (PLAN → SEARCH → FETCH → VALIDATE → FOLLOW-UP → SYNTHESIZE → LABEL) is intended behavior. The actual loop can be implemented as a helper in `/root/.hermes/scripts/firecrawl_local.py` or a dedicated module and invoked from `browser_exec`.
- The Crawl4AI-style retry/validation logic is a pattern only; it is not a dependency.
- SearXNG is an optional zero-cost backend; it requires a user-run instance.
- Firecrawl remains optional and never part of the default/deep path.

## Age-gates, DOM-queries, and related-crawl lessons (2026-09-07)

1. Click 18+ / age-verification gates before scraping adult sites; otherwise the real content is hidden.
2. Use DOM queries (`page.evaluate` / `document.querySelectorAll`) rather than HTML regex for JS-rendered cards.
3. When a site's search returns a fixed top set regardless of query, crawl recommended/related links from seed pages instead.
4. Multi-source beats single-source exhaustion: fan queries across free hosts and dedupe by URL.
5. When search engines are bot-walled, use the field's authoritative vertical press rather than fighting the search engine indefinitely.

## References

- Browser Automation — Hermes Agent docs: https://hermes-agent.nousresearch.com/docs/user-guide/features/browser
- Built-in Tools Reference — Hermes Agent: https://hermes-agent.nousresearch.com/docs/reference/tools-reference
- Toolsets Reference — Hermes Agent: https://hermes-agent.nousresearch.com/docs/reference/toolsets-reference
- Hermes Agent + Firecrawl: https://www.firecrawl.dev/blog/hermes-agent
- SearXNG: https://searxng.github.io/searxng/
- Crawl4AI: https://github.com/unclecode/crawl4ai
- Crawl4AI docs: https://docs.crawl4ai.com/
- GPT-Researcher: https://github.com/assafelovic/gpt-researcher
- GPT-Researcher docs: https://docs.gptr.ai/docs/gpt-researcher/gptr/deep_research
