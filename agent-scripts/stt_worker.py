#!/usr/bin/env python3
"""Lean out-of-process STT worker for Hermes (local faster-whisper).

Why: the Railway container has memory.max = 4.66 GiB while the Hermes gateway alone
holds ~2.3 GiB. Loading the 1.6 GB turbo model INSIDE the gateway (stt.provider=local)
peaks over the cgroup limit -> the kernel SIGKILLs the process (measured oom_kill=1,
exit 137). This worker keeps the model in a short-lived, import-light child process:
the 1.7 GB exists only while the call runs and is returned to the cgroup on exit.

Contract of HERMES_LOCAL_STT_COMMAND (tools/transcription_local.py::_transcribe_local_command):
  argv placeholders {input_path} {model} {output_dir} {language}; must write >=1 .txt
  into {output_dir}; 300 s timeout; runs with scrubbed credentials env.

Deliberately imports NOTHING from Hermes (no plugin stack): the extra ~300-500 MB of
hermes_cli plugin imports is what tipped the container over the limit in testing.
"""
from __future__ import annotations

import argparse
import gc
import os
import sys
from pathlib import Path

# Pin thread counts: ctranslate2 spawns per-core OpenMP threads and each one costs stack.
os.environ.setdefault("OMP_NUM_THREADS", "4")
os.environ.setdefault("CT2_VERBOSE", "0")


def _resolve_language(flag_value: str) -> str:
    """Resolve the transcription language without falling into the runner's "en" default.

    Hermes' local_command path substitutes its own DEFAULT_LOCAL_STT_LANGUAGE ("en") when
    stt.local.language is empty, and whisper then TRANSLATES non-English speech into English
    (observed live: Russian voice note came back in English). The in-process local provider
    instead passes no language at all and lets whisper auto-detect. Mirror that: honour the
    passed value only when it is a real explicit choice, otherwise read the config; empty = auto.
    """
    passed = (flag_value or "").strip()
    cfg_lang = ""
    try:
        import yaml  # present in the Hermes venv; worker stays import-light otherwise

        with open(os.environ.get("HERMES_CONFIG", "/root/.hermes/config.yaml")) as fh:
            stt = (yaml.safe_load(fh) or {}).get("stt") or {}
        cfg_lang = str((stt.get("local") or {}).get("language") or stt.get("language") or "").strip()
    except Exception:
        pass
    if passed and (passed != "en" or cfg_lang == "en"):
        return passed
    return cfg_lang


def _prefer_me_as_oom_victim() -> None:
    """Make THIS short-lived worker the kernel's first OOM victim instead of the gateway.

    The container ceiling is 4.66 GiB and the gateway baseline is ~2.2 GiB, so a transcription
    peak can still touch the limit. PID 1's oom_score_adj is not writable from inside the
    container, but our own is: +900 keeps the gateway (score ~670) alive and costs at most one
    transcript instead of a gateway restart.
    """
    try:
        with open("/proc/self/oom_score_adj", "w") as fh:
            fh.write("900")
    except Exception:
        pass


def _default_model() -> str:
    return os.environ.get("HERMES_STT_WORKER_MODEL") or "/opt/hermes-models/turbo-int8"


def main() -> int:
    _prefer_me_as_oom_victim()
    ap = argparse.ArgumentParser(description="Hermes local STT worker (faster-whisper)")
    ap.add_argument("input_path")
    ap.add_argument("--model", default=_default_model())
    ap.add_argument("--output_dir", required=True)
    ap.add_argument("--language", default="")
    ap.add_argument("--compute_type", default="int8")
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--no-vad", action="store_true")
    args = ap.parse_args()

    from faster_whisper import WhisperModel

    model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)
    kwargs = {
        "beam_size": 5,
        "condition_on_previous_text": False,  # one hallucinated token must not seed a run
        "vad_filter": not args.no_vad,
    }
    if kwargs["vad_filter"]:
        kwargs["vad_parameters"] = {"min_silence_duration_ms": 500}
    kwargs["no_speech_threshold"] = 0.6
    kwargs["log_prob_threshold"] = -1.0
    resolved_language = _resolve_language(args.language)
    if resolved_language:
        kwargs["language"] = resolved_language

    segments, info = model.transcribe(args.input_path, **kwargs)
    no_speech, logprob = 0.6, -1.0
    kept: list[str] = []
    for seg in segments:
        try:
            if float(seg.no_speech_prob) > no_speech and float(seg.avg_logprob) < logprob:
                continue  # probable silence hallucination (AND gate, same as Hermes)
        except (AttributeError, TypeError, ValueError):
            pass
        kept.append(seg.text.strip())
    text = " ".join(kept).strip()

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / (Path(args.input_path).stem + ".txt")).write_text(text, encoding="utf-8")
    print(f"stt_worker: model={args.model} lang={info.language} audio={info.duration:.1f}s "
          f"chars={len(text)}", file=sys.stderr)
    del model
    gc.collect()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
