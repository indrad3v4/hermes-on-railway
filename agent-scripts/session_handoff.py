#!/usr/bin/env python3
"""session_handoff.py — deterministic, zero-token session handoff.

TRIZ problem #1 resolution (Kukalev 1.6.6 «разделение в структуре ИС: вся система
наделяется свойством С, а её части — свойством анти-С»):
  the MEMORY system is long-lived (this file, cheap at rest),
  the SESSION is short-lived (working set, closed when the task ends).
The bridge is this handoff — written BEFORE closing (№10 предварительное действие),
built from what is durably useful (№22 обратная связь).

No LLM call: pure regex/SQL extraction, so it runs as a `quick_commands: type: exec`
and costs $0 and ~0 s of model time.

Usage:
    session_handoff.py                  # handoff the most recently active session
    session_handoff.py --session <id>   # handoff a specific session
    session_handoff.py --brief [<id>]   # print a stored brief (latest by default)
    session_handoff.py --list           # list stored handoffs
    session_handoff.py --threshold 25   # exit 0 if session needs a handoff, 3 if not
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone

DB = os.path.expanduser("~/.hermes/state.db")
OUT_DIR = os.path.expanduser("~/.hermes/state/handoffs")

# Artifacts worth carrying: absolute paths, urls, commit shas, kanban ids, model ids.
RE_PATH = re.compile(r"(?<![\w/])(/(?:root|opt|tmp|etc|usr|var)/[\w./\-\u0400-\u04FF]{3,120})")
RE_URL = re.compile(r"https?://[^\s\"'<>)\]]{6,180}")
RE_SHA = re.compile(r"\b([0-9a-f]{7,40})\b")
RE_CARD = re.compile(r"\b(t_[0-9a-f]{6,10})\b")
RE_KV = re.compile(r"\b([a-z_]+(?:\.[a-z_]+)*)\s*[:=]\s*([^\s,;|]+)")

# Lines that announce a durable decision (RU/EN).
DECISION_MARKERS = (
    "готово", "запушено", "задепло", "решили", "решено", "подтвержд", "проверено",
    "включен", "включён", "применен", "применён", "установлен", "создан", "закреп",
    "done", "shipped", "deployed", "verified", "enabled", "applied", "merged",
)
# Lines that are noise for a handoff.
NOISE = ("[SKILL_PRUNED", "MEDIA:/root/.hermes/media/cards/", "Continue from where",
         "This session is being continued")


def connect() -> sqlite3.Connection:
    return sqlite3.connect(f"file:{DB}?mode=ro", uri=True)


def pick_session(cur, wanted: str | None) -> str | None:
    if wanted:
        return wanted
    row = cur.execute(
        "SELECT id FROM sessions WHERE source != 'subagent' "
        "ORDER BY COALESCE(last_activity_at, 0) DESC LIMIT 1"
    ).fetchone()
    return row[0] if row else None


def session_meta(cur, sid: str) -> dict:
    cols = [d[1] for d in cur.execute("PRAGMA table_info(sessions)")]
    want = [c for c in ("id", "source", "chat_type", "thread_id", "display_name", "message_count",
                        "api_call_count", "estimated_cost_usd", "started_at", "last_activity_at",
                        "input_tokens", "cache_read_tokens", "title") if c in cols]
    row = cur.execute(f"SELECT {','.join(want)} FROM sessions WHERE id=?", (sid,)).fetchone()
    if not row:
        return {}
    meta = dict(zip(want, row))
    t0 = cur.execute("SELECT MIN(timestamp), MAX(timestamp) FROM messages WHERE session_id=?", (sid,)).fetchone()
    meta["_min_ts"], meta["_max_ts"] = (t0[0], t0[1]) if t0 else (None, None)
    meta["_rows"] = cur.execute("SELECT COUNT(*) FROM messages WHERE session_id=?", (sid,)).fetchone()[0]
    return meta


def extract(cur, sid: str) -> dict:
    """Deterministic durable extraction. No model, no guessing."""
    paths, urls, shas, cards, cmds, decisions, open_user = [], [], [], [], [], [], []
    seen_paths, seen_urls = set(), set()

    for role, content, tool_name, tcs in cur.execute(
        "SELECT role, content, tool_name, tool_calls FROM messages "
        "WHERE session_id=? ORDER BY timestamp", (sid,),
    ):
        blob = (content or "") + " " + (tcs or "")
        for p in RE_PATH.findall(blob):
            if p not in seen_paths and not p.startswith("/root/.hermes/media/cards"):
                seen_paths.add(p); paths.append(p)
        for u in RE_URL.findall(blob):
            if u not in seen_urls:
                seen_urls.add(u); urls.append(u)
        for c in RE_CARD.findall(blob):
            if c not in cards:
                cards.append(c)
        for s in RE_SHA.findall(blob):
            if len(s) >= 7 and not s.isdigit() and s not in shas:
                shas.append(s)
        if tool_name == "terminal" and content:
            m = re.search(r'"command":\s*"(.{1,200})', content)
            if m:
                cmd = m.group(1).replace("\\n", " ").strip()
                if cmd not in cmds:
                    cmds.append(cmd)
        if role == "assistant" and content and not any(n in content for n in NOISE):
            for line in content.splitlines():
                low = line.lower().strip()
                if 20 <= len(line.strip()) <= 300 and any(k in low for k in DECISION_MARKERS):
                    text = line.strip().lstrip("-•*0123456789. ").strip()
                    if text and text not in decisions:
                        decisions.append(text)
                    break
        if role == "user" and content and "[OUT-OF-BAND" not in content and not content.startswith("[Cron"):
            open_user.append(" ".join(content.split())[:300])

    return {
        "paths": paths[-40:], "urls": urls[-25:], "shas": shas[-10:],
        "cards": cards[-20:], "commands": cmds[-25:],
        "decisions": decisions[-25:], "recent_user": open_user[-8:],
    }


def fmt_ts(ts) -> str:
    try:
        return datetime.fromtimestamp(float(ts), tz=timezone.utc).strftime("%m-%d %H:%M")
    except Exception:
        return "?"


def build_brief(meta: dict, ex: dict) -> str:
    sid = meta.get("id", "?")
    cost = meta.get("estimated_cost_usd") or 0
    lines = [
        f"# HANDOFF {sid}",
        f"source={meta.get('source')} thread={meta.get('thread_id')} "
        f"rows={meta.get('_rows')} api_calls={meta.get('api_call_count')} cost=${cost:.3f}",
        f"span={fmt_ts(meta.get('_min_ts'))} -> {fmt_ts(meta.get('_max_ts'))}",
        "",
        "## ЧТО РЕШЕНО (durable)",
    ]
    lines += [f"- {d}" for d in ex["decisions"]] or ["- (не распознано)"]
    lines += ["", "## АРТЕФАКТЫ (пути)"]
    lines += [f"- {p}" for p in ex["paths"]] or ["- (нет)"]
    if ex["urls"]:
        lines += ["", "## ССЫЛКИ"] + [f"- {u}" for u in ex["urls"]]
    if ex["cards"]:
        lines += ["", "## KANBAN-КАРТОЧКИ"] + [f"- {c}" for c in ex["cards"]]
    if ex["shas"]:
        lines += ["", "## КОММИТЫ"] + [f"- {s}" for s in ex["shas"]]
    if ex["commands"]:
        lines += ["", "## КОМАНДЫ"] + [f"- {c}" for c in ex["commands"]]
    lines += ["", "## ОТКРЫТЫЕ НИТИ (последние запросы)"] + [f"- {u}" for u in ex["recent_user"]] or ["- (нет)"]
    lines += [
        "",
        "## ПОДХВАТ В НОВОЙ СЕССИИ",
        f"1) session_search по ключевым словам задачи",
        f"2) hermes sessions export {sid}  (полный архив, если нужна деталь)",
        f"3) handoff-файл: ~/.hermes/state/handoffs/{sid}.txt",
    ]
    return "\n".join(lines)


def cmd_handoff(args) -> int:
    con = connect(); cur = con.cursor()
    sid = pick_session(cur, args.session)
    if not sid:
        print("ERR: no session found"); return 1
    meta = session_meta(cur, sid)
    ex = extract(cur, sid)
    brief = build_brief(meta, ex)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{sid}.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(brief + "\n")
    with open(os.path.join(OUT_DIR, "latest"), "w", encoding="utf-8") as f:
        f.write(sid)
    print(f"HANDOFF WRITTEN: {path}  ({len(brief)} chars)")
    print()
    print(brief)
    return 0


def cmd_brief(args) -> int:
    sid = args.brief
    if not sid:
        lp = os.path.join(OUT_DIR, "latest")
        if not os.path.exists(lp):
            print("ERR: no handoffs yet — run /handoff first"); return 1
        sid = open(lp, encoding="utf-8").read().strip()
    path = os.path.join(OUT_DIR, f"{sid}.txt")
    if not os.path.exists(path):
        print(f"ERR: no handoff for {sid}"); return 1
    print(open(path, encoding="utf-8").read())
    return 0


def cmd_list(args) -> int:
    if not os.path.isdir(OUT_DIR):
        print("(no handoffs yet)"); return 0
    for f in sorted(os.listdir(OUT_DIR)):
        if f.endswith(".txt"):
            p = os.path.join(OUT_DIR, f)
            print(f"{os.path.basename(f)[:-4]}  {os.path.getsize(p)} B  {fmt_ts(os.path.getmtime(p))}")
    return 0


def cmd_threshold(args) -> int:
    """Exit 3 = 'nothing to do' (silent tick for cron), 0 = handoff advisable."""
    con = connect(); cur = con.cursor()
    sid = pick_session(cur, args.session)
    if not sid:
        return 3
    meta = session_meta(cur, sid)
    rows = meta.get("_rows") or 0
    cost = meta.get("estimated_cost_usd") or 0.0
    stamp = os.path.join(OUT_DIR, f"{sid}.txt")
    fresh = os.path.exists(stamp) and os.path.getmtime(stamp) >= (meta.get("last_activity_at") or 0)
    if fresh or rows < args.threshold:
        return 3
    print(f"SUGGEST HANDOFF: session {sid} has {rows} messages / ${cost:.2f} with no handoff since it grew.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--session")
    ap.add_argument("--brief", nargs="?", const="", default=None)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--threshold", type=int, default=0)
    a = ap.parse_args()
    if a.list:
        return cmd_list(a)
    if a.brief is not None:
        return cmd_brief(a)
    if a.threshold:
        return cmd_threshold(a)
    return cmd_handoff(a)


if __name__ == "__main__":
    sys.exit(main())
