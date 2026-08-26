"""Transcribe a WAV file with faster-whisper (large-v3) on GPU.

Outputs <base>.txt, <base>.srt, <base>.json next to the input.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

import srt
from faster_whisper import WhisperModel


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("audio", type=Path)
    p.add_argument("--language", default="de")
    p.add_argument("--model", default="large-v3")
    p.add_argument("--compute-type", default="float16")
    p.add_argument("--beam-size", type=int, default=5)
    args = p.parse_args()

    base = args.audio.with_suffix("")
    print(f"Loading model {args.model} on cuda/{args.compute_type} ...", flush=True)
    model = WhisperModel(args.model, device="cuda", compute_type=args.compute_type)

    print(f"Transcribing {args.audio} (lang={args.language}) ...", flush=True)
    segments, info = model.transcribe(
        str(args.audio),
        language=args.language,
        vad_filter=True,
        beam_size=args.beam_size,
    )

    txt_path = base.with_suffix(".txt")
    srt_path = base.with_suffix(".srt")
    json_path = base.with_suffix(".json")

    rows: list[dict] = []
    subs: list[srt.Subtitle] = []
    with txt_path.open("w", encoding="utf-8") as f_txt:
        for i, s in enumerate(segments, start=1):
            text = s.text.strip()
            f_txt.write(text + "\n")
            rows.append({"start": s.start, "end": s.end, "text": text})
            subs.append(
                srt.Subtitle(
                    index=i,
                    start=dt.timedelta(seconds=s.start),
                    end=dt.timedelta(seconds=s.end),
                    content=text,
                )
            )
            if i % 25 == 0:
                print(f"  segment {i}: {s.end:8.1f}s  {text[:80]}", flush=True)

    srt_path.write_text(srt.compose(subs), encoding="utf-8")
    json_path.write_text(
        json.dumps(
            {
                "language": info.language,
                "language_probability": info.language_probability,
                "duration": info.duration,
                "segments": rows,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"OK. Wrote:\n  {txt_path}\n  {srt_path}\n  {json_path}")


if __name__ == "__main__":
    main()
