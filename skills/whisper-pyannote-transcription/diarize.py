"""Speaker diarization with pyannote/speaker-diarization-3.1 + merge with whisper segments.

Inputs:
  --audio  <wav>   16 kHz mono WAV (same one used for transcription)
  --json   <json>  Whisper output JSON from transcribe.py

Outputs (same base as --json):
  <base>.diarized.json  segments with "speaker" field
  <base>.diarized.srt   SRT with "[SPEAKER_xx] text" lines
  <base>.diarized.txt   plain text grouped by speaker turn
  <base>.rttm           pyannote raw RTTM
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from collections import defaultdict
from pathlib import Path

import srt
import torch
import torchaudio
from pyannote.audio import Pipeline


def overlap(a0: float, a1: float, b0: float, b1: float) -> float:
    return max(0.0, min(a1, b1) - max(a0, b0))


def assign_speakers(segments: list[dict], turns: list[tuple[float, float, str]]) -> None:
    """For each whisper segment, attach the speaker label with most overlap."""
    for seg in segments:
        best_speaker = "UNKNOWN"
        best_overlap = 0.0
        for t0, t1, spk in turns:
            ov = overlap(seg["start"], seg["end"], t0, t1)
            if ov > best_overlap:
                best_overlap = ov
                best_speaker = spk
        seg["speaker"] = best_speaker


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--audio", type=Path, required=True)
    p.add_argument("--json", type=Path, required=True, help="whisper transcribe.py JSON")
    p.add_argument("--model", default="pyannote/speaker-diarization-3.1")
    p.add_argument("--num-speakers", type=int, default=None)
    p.add_argument("--min-speakers", type=int, default=None)
    p.add_argument("--max-speakers", type=int, default=None)
    args = p.parse_args()

    token = os.environ.get("HF_TOKEN")
    if not token:
        raise SystemExit("HF_TOKEN environment variable not set")

    print(f"Loading {args.model} ...", flush=True)
    try:
        pipeline = Pipeline.from_pretrained(args.model, token=token)
    except TypeError:
        # older pyannote versions
        pipeline = Pipeline.from_pretrained(args.model, use_auth_token=token)
    if torch.cuda.is_available():
        pipeline.to(torch.device("cuda"))
        print(f"Pipeline on GPU: {torch.cuda.get_device_name(0)}", flush=True)
    else:
        print("WARNING: running on CPU", flush=True)

    print(f"Loading audio {args.audio} ...", flush=True)
    waveform, sample_rate = torchaudio.load(str(args.audio))

    print("Running diarization ...", flush=True)
    kwargs: dict = {}
    if args.num_speakers is not None:
        kwargs["num_speakers"] = args.num_speakers
    if args.min_speakers is not None:
        kwargs["min_speakers"] = args.min_speakers
    if args.max_speakers is not None:
        kwargs["max_speakers"] = args.max_speakers
    diarization = pipeline({"waveform": waveform, "sample_rate": sample_rate}, **kwargs)

    base = args.json.with_suffix("")  # strips .json
    rttm_path = Path(str(base) + ".rttm")
    with rttm_path.open("w", encoding="utf-8") as f:
        diarization.write_rttm(f)
    print(f"Wrote {rttm_path}", flush=True)

    turns: list[tuple[float, float, str]] = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        turns.append((turn.start, turn.end, speaker))
    print(f"  {len(turns)} speaker turns, "
          f"{len({s for _, _, s in turns})} unique speakers", flush=True)

    print(f"Merging speakers into {args.json} ...", flush=True)
    data = json.loads(args.json.read_text(encoding="utf-8"))
    segments = data["segments"]
    assign_speakers(segments, turns)

    out_json = Path(str(base) + ".diarized.json")
    out_srt = Path(str(base) + ".diarized.srt")
    out_txt = Path(str(base) + ".diarized.txt")

    out_json.write_text(
        json.dumps(
            {**data, "speaker_turns": [[s, e, sp] for s, e, sp in turns],
             "segments": segments},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    subs = [
        srt.Subtitle(
            index=i,
            start=dt.timedelta(seconds=s["start"]),
            end=dt.timedelta(seconds=s["end"]),
            content=f"[{s['speaker']}] {s['text']}",
        )
        for i, s in enumerate(segments, start=1)
    ]
    out_srt.write_text(srt.compose(subs), encoding="utf-8")

    # Group consecutive segments by same speaker into prose blocks
    grouped: list[tuple[str, float, float, list[str]]] = []
    for s in segments:
        if grouped and grouped[-1][0] == s["speaker"]:
            grouped[-1][3].append(s["text"])
            grouped[-1] = (grouped[-1][0], grouped[-1][1], s["end"], grouped[-1][3])
        else:
            grouped.append((s["speaker"], s["start"], s["end"], [s["text"]]))

    with out_txt.open("w", encoding="utf-8") as f:
        for spk, t0, t1, lines in grouped:
            f.write(f"\n[{spk} {dt.timedelta(seconds=int(t0))}–{dt.timedelta(seconds=int(t1))}]\n")
            f.write(" ".join(lines).strip() + "\n")

    speakers = defaultdict(float)
    for s in segments:
        speakers[s["speaker"]] += s["end"] - s["start"]
    print("\nSpeaker time (s):")
    for spk, secs in sorted(speakers.items(), key=lambda x: -x[1]):
        print(f"  {spk:14s} {secs:8.1f}")

    print(f"\nOK. Wrote:\n  {out_json}\n  {out_srt}\n  {out_txt}")


if __name__ == "__main__":
    main()
