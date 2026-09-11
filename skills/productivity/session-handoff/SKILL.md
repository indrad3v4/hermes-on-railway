---
name: session-handoff
description: "Use when a session grows long — hand off, then start fresh."
version: 1.0.0
---

# Session Handoff — long memory, short sessions

Indra's rule: he refuses to repeat himself, so "just start a new session" is not an
answer. This skill is the bridge that makes a new session start with ZERO repetition.

## The contradiction this resolves (TRIZ)

Problem #1 from the token-economics audit: the busiest Telegram thread ran for 2 days
in one session — every turn re-sent a 303 031-token prefix (~91% of all spend was
session bulk, not crons and not cache misses).

- **ТП:** «если держать одну бессмертную сессию, ТО сквозная память есть, НО каждый ход
  пересылает весь префикс → расход растёт линейно с длиной».
- **ФП:** «сессия должна быть ДЛИННОЙ (чтобы помнить) и КОРОТКОЙ (чтобы не платить)».
- **Разрешение (Кукалев, гл. 1.6.6, «разделение в структуре ИС»):** «вся система
  наделяется свойством С, а её части — свойством анти-С» → **память (система) длинная,
  сессия (часть) короткая**. Мост = заранее записанный handoff
  (**№2 вынесение** + **№10 предварительное действие** + **№22 обратная связь**).
- **ИКР:** новая сессия открывается, и повторять не нужно ничего. Проверка: сколько раз
  владелец повторил уже сказанное в первой сессии после handoff. Цель — ноль.

## Commands (all `quick_commands`, `type: exec` — zero tokens)

| Command | What it does |
|---|---|
| `/handoff` | Writes the handoff for the most recent session and prints it. **Run BEFORE `/new`.** |
| `/brief` | Prints the stored handoff (latest, or `--session <id>`). **Run FIRST in the new session.** |
| `/handoffs` | Lists stored handoffs with size + age. |

Implementation: `~/.hermes/scripts/session_handoff.py` (deterministic SQL + regex, no LLM).
Watchdog: `~/.hermes/scripts/handoff_watch.sh` — cron `Handoff nudge (no-agent)`, hourly,
`no_agent=True`, silent unless a live session passes the message threshold.

## The protocol

1. **Before closing** a session that did real work: run `/handoff`. It writes
   `~/.hermes/state/handoffs/<session_id>.txt` and prints the brief.
2. **Start the new session** and paste the brief as the first message (or run `/brief`).
3. The brief carries only durable things: decisions, artifact paths, URLs, kanban card ids,
   commit shas, commands, and the last few open asks.
4. **Detail on demand** — never pre-load the transcript. For a specific fact use
   `session_search`; for the full archive `hermes sessions export <id>`.
5. **№22 feedback** — when the brief missed something you had to look up, add that item
   to the extraction rules in `session_handoff.py`; do not bulk-grow the brief.

## What goes in the brief (and what does not)

- IN: decisions with their evidence, absolute artifact paths, URLs, `t_*` card ids, commit
  shas, config keys set, open threads.
- OUT: raw tool dumps, full file contents, chat pleasantries, anything already in `memory`
  or in a kanban card (link it instead of copying it).

## Pitfalls

- **Do not run `/handoff` after `/new`** — the old session id must still be the most recently
  active one, otherwise pass `--session <id>` explicitly.
- The nudge is a hint, not an action: it never auto-closes a session.
- `messages.token_count` is NULL in this box's state.db — cost comes from
  `session_model_usage` / `sessions.estimated_cost_usd`, not from per-message counts.
- Extraction is heuristic: skim the brief before pasting it. A line that matched a decision
  marker by accident is cheap to delete; a missing decision is not.
- Session bulk is only ~62% of spend. This skill does not replace the compression settings
  (`proactive_prune_tokens`, `micro_compact`, `threshold`) — they are complementary.
