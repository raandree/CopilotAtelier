---
name: whisper-pyannote-transcription
description: >-
  Transcribe long audio/video on Windows with GPU acceleration using
  faster-whisper (CTranslate2) and add speaker labels with pyannote.audio.
  Covers ffmpeg audio extraction, Python 3.12 venv isolation, CUDA-matched
  PyTorch wheel selection, faster-whisper large-v3 inference, pyannote 3.1
  speaker diarization with Hugging Face gated-model access, and merging
  speaker turns into Whisper segments to produce speaker-labeled SRT, JSON,
  and grouped transcript text. Includes the Windows-specific torchcodec
  bypass (preload waveform via torchaudio) and the Tee-Object exit-code
  trap.
  USE FOR: transcribe video, transcribe audio, faster-whisper, whisper GPU,
  large-v3, ctranslate2, pyannote.audio, speaker diarization, speaker
  labels, who spoke when, RTTM, SRT subtitles, transcribe MP4, transcribe
  WAV, German transcription, mixed language transcription, ffmpeg audio
  extract, 16 kHz mono WAV, Hugging Face gated model, HF_TOKEN, HF 403
  Forbidden, GatedRepoError, pyannote/speaker-diarization-3.1, RTX 4080
  transcription, CUDA torch wheel, cu128, Python 3.12 venv, torchcodec
  Windows, torchcodec libtorchcodec_core, CPU torch fallback bug.
  DO NOT USE FOR: real-time streaming transcription, dictation UIs, cloud
  transcription APIs (Azure Speech, AWS Transcribe), audio editing, audio
  enhancement / denoising, voice cloning, TTS.
---

# Whisper + Pyannote Transcription with Speaker Labels

End-to-end pipeline to transcribe long recordings on a Windows GPU workstation and attach speaker identifiers to each segment.

## When to Use

- Multi-hour meeting recording, interview, or video that needs a searchable transcript
- Recording has multiple speakers and you want "who said what"
- Local GPU available (RTX 30xx/40xx class); cloud APIs not desired
- Multilingual audio (e.g. German with English passages) — Whisper handles it natively

## Architecture

```
video.mp4
   │  ffmpeg  -ac 1 -ar 16000  (≈100× shrink)
   ▼
audio.wav (16 kHz mono PCM)
   │
   ├─► faster-whisper large-v3 (CUDA, float16) ─► .txt + .srt + .json
   │
   └─► pyannote/speaker-diarization-3.1 (CUDA) ─► .rttm
                                                     │
                       merge by max-overlap          │
        whisper.json + .rttm  ──────────────────────►├─► .diarized.json
                                                     ├─► .diarized.srt
                                                     └─► .diarized.txt
```

## Pitfalls

These all bit during initial implementation. Read before running.

| # | Pitfall | Fix |
|---|---|---|
| 1 | `pip install torch` defaults to **CPU-only** wheels from PyPI | Always use `--index-url https://download.pytorch.org/whl/cuXXX` matching the driver |
| 2 | Re-installing torch after a CPU build silently keeps CPU wheel | `pip uninstall -y torch torchaudio torchcodec` first |
| 3 | pyannote.audio ≥ 4.0 requires torch ≥ 2.8 | Use `cu128` channel (`cu124` caps at torch 2.6) |
| 4 | pyannote.audio 4.x renamed `use_auth_token` → `token` | `try`/`except TypeError` covering both |
| 5 | `torchcodec` fails on Windows with winget's Gyan.FFmpeg "full" build | Pre-load audio with `torchaudio.load`; pass `{waveform, sample_rate}` dict to pipeline |
| 6 | HF returns `403 GatedRepoError` despite valid token | Click "Agree" on **both** `pyannote/speaker-diarization-3.1` AND `pyannote/segmentation-3.0` |
| 7 | Python 3.13/3.14 has no compatible wheels for ctranslate2 / pyannote | Install Python 3.12 in a dedicated venv |
| 8 | `winget install` updates PATH but the current shell does not see it | `$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')` |
| 9 | `Tee-Object` exits with code 1 when final stdout has non-ASCII | Verify outputs by file existence/size, not exit code |
| 10 | Console shows mojibake (`Σ ⁿ ÷ ▀`) for German umlauts | Cosmetic only — files are written UTF-8; check the `.txt`, not the console |
| 11 | Reading the Tee log file fails with sharing violation | Use the Python script's own output files instead of the log |
| 12 | **Long transcripts (>30 min) loop and bleed languages without `condition_on_previous_text=False`** | Always pass `--no-condition` for long-form / mixed-language audio; default `True` causes Whisper to anchor on prior segments and drift |
| 13 | **Glossar (`initial_prompt`) reduces but does not eliminate proper-noun errors** | Whisper still hallucinates rare proper nouns (e.g. "Replit" → "PocketOS", or a small-town name rendered as a phonetic neighbor) even with the name listed in the prompt; plan a post-processing regex pass |
| 14 | **Mixed-language recordings (e.g. a German segment followed by an English segment in one file) corrupt under single `--language`** | Split by offset and run two passes: `--start 0 --end <switch> --language de`, then `--start <switch> --end <total> --language en`. Each with its own glossary |
| 15 | **Whisper is non-deterministic across runs at the segment level** | Two runs with same audio + same params can give different wording in difficult passages. For high-stakes content, run focus-passages 2–3 times with `--beam-size 10–15` and accept the majority reading |
| 16 | **Mechanical bulk regex pass on the master SRT can silently overwrite a focus-verified reading** | A focus pass resolves a Whisper artefact acoustically (e.g. `the light question` → `<NamedEntity>`). A later sed/regex bulk pass — typically applied to fix systemic acronym errors across the whole SRT — sees the *same* artefact and resolves it to the *grammatically nearest* candidate (often a personal pronoun like `I` or `he`), overwriting the focus-verified reading. After every bulk pass, `grep` for the focus-verified phrase fragments and confirm the surrounding subject still matches the verification table; if the master SRT disagrees with the focus pass, the focus pass wins. See Recipe 5 → *Cross-stage consistency*. |
| 17 | **Whisper hallucinations on single-syllable subject phrases have more than one plausible resolution** | When the artefact is a function-word noun phrase (`the light question`, `the life question`, `the staff/South`, `the sound`), the correct subject is rarely the grammatically nearest pronoun. Always cross-check against domain-coherent secondary sources (user notes, follow-up emails, prior focus passes) before committing a mechanical resolution. The acoustically correct resolution is often a named entity that is invisible to the regex pass. |

## Prerequisites

| Component | Version tested | Install |
|---|---|---|
| Windows + NVIDIA driver | CUDA 12.8 capable (≥ 572.x) | OEM |
| ffmpeg | 8.x full | `winget install --id Gyan.FFmpeg -e` |
| Python | 3.12.x | `winget install --id Python.Python.3.12 -e` |
| Hugging Face account | with read token | https://huggingface.co/settings/tokens |
| HF gated model access | accepted licenses | see Recipe 4 |

### Verify CUDA visibility

```powershell
nvidia-smi | Select-String 'NVIDIA|CUDA' | Select-Object -First 3
```

## Recipe 1 — Extract 16 kHz mono WAV

Whisper resamples to 16 kHz mono internally, so do this once with ffmpeg and reuse the WAV for both transcription and diarization. A multi-GB MP4 collapses to a few hundred MB of WAV.

```powershell
ffprobe -v error `
  -show_entries format=duration,bit_rate `
  -show_entries stream=codec_type,codec_name,channels,sample_rate `
  -of default=nw=1 `
  '<input.mp4>'

ffmpeg -y -i '<input.mp4>' `
  -vn -ac 1 -ar 16000 -c:a pcm_s16le `
  '<input>.wav' `
  -hide_banner -loglevel warning -stats
```

## Recipe 2 — Create the GPU venv

```powershell
py -3.12 -m venv <venvPath>
& '<venvPath>\Scripts\python.exe' -m pip install --upgrade pip wheel

# faster-whisper + CUDA runtime DLLs (cuBLAS, cuDNN) for ctranslate2
& '<venvPath>\Scripts\python.exe' -m pip install `
    faster-whisper srt nvidia-cublas-cu12 nvidia-cudnn-cu12

# CUDA-enabled PyTorch (matches NVIDIA driver's CUDA major)
& '<venvPath>\Scripts\python.exe' -m pip install `
    --index-url https://download.pytorch.org/whl/cu128 `
    torch torchaudio

# Diarization stack
& '<venvPath>\Scripts\python.exe' -m pip install `
    'pyannote.audio>=3.3' torchcodec
```

### Verify GPU torch

```powershell
& '<venvPath>\Scripts\python.exe' -c `
  "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

Expected: `2.11.0+cu128 True NVIDIA GeForce RTX ...`. If it prints `+cpu` or `False`, see pitfalls 1–3.

## Recipe 3 — Transcribe

Use the script in this skill's `transcribe.py` (also reproduced below).

```powershell
& '<venvPath>\Scripts\python.exe' '<skillDir>\transcribe.py' '<input>.wav' `
    --language de --model large-v3
```

Outputs next to the WAV:

| File | Content |
|---|---|
| `<input>.txt` | One segment per line, plain text |
| `<input>.srt` | Subtitle file with timestamps |
| `<input>.json` | `{language, language_probability, duration, segments[]}` |

**Throughput**: RTX 4080 Laptop with `large-v3` float16 transcribes ≈ 2 h of audio in ≈ 30 min.

**Language**: pass `--language de` for German, `--language en` for English, or omit for auto-detect. Whisper handles in-segment language switching even when a primary language is set.

## Recipe 3b — Transcribe a segment with glossary (recommended for long / mixed-language)

Use the script in this skill's `transcribe-segment.py`. It supports offset/end windows, an `initial_prompt` glossary file, and disables `condition_on_previous_text` to prevent loops.

```powershell
& '<venvPath>\Scripts\python.exe' '<skillDir>\transcribe-segment.py' '<input>.wav' `
    --start 0 --end 2780 --language de --suffix '_cs_de' `
    --initial-prompt-file 'glossary_de.txt' --no-condition
```

**Glossary file format** (UTF-8 plain text, single paragraph, < ~250 tokens):

```
Conversation between PersonA (role) and PersonB (role).
Key terms: ProductName, AcronymOne, AcronymTwo, CustomerName, ProjectCode,
likely-to-be-mistranscribed brand names, internal jargon ...
```

Whisper uses this as `initial_prompt`, biasing it toward those tokens. **It is not a hard constraint** — see Pitfall 13.

### Mixed-language recording pattern (e.g. a German segment followed by an English segment in one MP4)

Always split:

```powershell
# DE half
& py 'transcribe-segment.py' meeting.wav --start 0    --end 2780 `
    --language de --suffix '_de' --initial-prompt-file glossary_de.txt --no-condition

# EN half
& py 'transcribe-segment.py' meeting.wav --start 2780 --end 7125 `
    --language en --suffix '_en' --initial-prompt-file glossary_en.txt --no-condition
```

A single-pass `--language de` over a mixed file produced these failure modes in production:

- The DE half got correctly transcribed.
- The EN half got transcribed *as if it were broken German*: `"performance was rated very negatively"` rendered with German segment metadata, mojibake umlauts in the WAV-level mid-segment.
- VAD + language anchoring produced lookahead loops where short EN phrases repeated 3–5×.

Splitting fixes all three failure modes.

## Recipe 4 — Speaker diarization

### Accept the licenses (one-time per HF account)

1. https://huggingface.co/pyannote/speaker-diarization-3.1 → "Agree and access repository"
2. https://huggingface.co/pyannote/segmentation-3.0 → "Agree and access repository"
3. https://huggingface.co/settings/tokens → create a **read** token

```powershell
[Environment]::SetEnvironmentVariable('HF_TOKEN', '<your-read-token>', 'User')
$env:HF_TOKEN = '<your-read-token>'
```

### Run diarization

```powershell
& '<venvPath>\Scripts\python.exe' '<skillDir>\diarize.py' `
    --audio '<input>.wav' --json '<input>.json'
```

Optional speaker count hints: `--num-speakers N`, or `--min-speakers M --max-speakers N`.

Outputs:

| File | Content |
|---|---|
| `<input>.rttm` | Raw pyannote RTTM (speaker turns) |
| `<input>.diarized.json` | Whisper segments with `speaker` field plus `speaker_turns[]` |
| `<input>.diarized.srt` | SRT lines prefixed `[SPEAKER_xx] ` |
| `<input>.diarized.txt` | Text grouped into speaker turns with start/end timestamps |

### Diagnostic: 403 GatedRepoError

If `Pipeline.from_pretrained` raises `GatedRepoError`, the token is valid but one of the two licenses has not been accepted on the same HF account. Re-check both URLs above; they show "You have been granted access" once accepted.

## Recipe 5 — Verify critical passages with focused re-transcription

When a transcript is used as evidence (legal, HR, contractual) or to extract verbatim quotes, single-pass Whisper output is **not** sufficient. Whisper:

1. Hallucinates rare proper nouns even with a glossary (Pitfall 13).
2. Is non-deterministic at the segment level (Pitfall 15).
3. Mishears semantically critical short phrases (e.g. flips a domain-specific term into a near-homophone, or turns a declarative subject phrase into a question).

### Pattern: focused re-transcription with majority voting

For each critical passage you intend to quote:

1. Identify the **timestamp window** in the full transcript (~30–90 seconds; pad ±10 s).
2. Re-transcribe just that window with stronger settings:

```powershell
& py 'transcribe-segment.py' meeting.wav `
    --start 3370 --end 3460 --language en `
    --suffix '_focus_passage_a' `
    --initial-prompt-file glossary_en.txt --no-condition `
    --beam-size 10
```

3. Compare the focused text against the full-pass text segment by segment.
4. If they match → confidence high; quote with timestamp anchor.
5. If they differ → run a second focus pass with `--beam-size 15` and a slightly larger window.
6. **Two of three passes agree → majority reading wins**; document the dissenting reading.
7. **All three passes disagree → the passage is not quotable**; cite only the timestamp and the original audio file. Do not paraphrase a guess.

### Real-world example (anonymized verification pattern)

From a 2-hour mixed-language recording, six critical passages were re-verified:

| Passage | v1 (default) | v2 (glossary, no-condition) | Focus (beam=10) | Decision |
|---|---|---|---|---|
| Subject of action statement | `<SubjectA>, will you be required, as a manager,` (question) | `the life question will be required as a manager` (truncated) | `<SubjectA> will be required as a manager to take Action X, which is very specific` | **Focus reading wins** |
| Domain-specific rating term | `flagged with a lie` | `flagged with a <Term>` | `plagued with a lot` | **v2 wins** (domain-canonical term) |
| Prepositional object | `cultural fit for <Org>` | `cultural fit for <Org>` | `control over <Org>` | **v1+v2 win** (2 vs 1) |
| Time reference | `put on hold in Q3` | `put on hold in Q3` | `put on hold in T2` | **v1+v2 win** (Q3 maps to a real fiscal quarter) |
| Numeric amount | `<Amount> on the table` | `<Amount> on the table, plus six months at the time of the sign-off` | `<Amount> on the table, plus six months at the time of the signing off, had to go to <PersonC> because it was fairly large` | **Focus wins** (richest, all consistent) |
| Trailing currency phrase | `going to be <Amount2>` | `going to be <Amount2>` | `is turning <Amount2> of us` | **Not quotable** — all three disagree on syntax; cite timestamp only |

### Glossary as a drag, not a steering wheel

The glossary in this verification did:

- Reduce DE umlaut mojibake to zero (compared to the v1 console output).
- Recover listed domain acronyms (`<ACRO1>`, `<ACRO2>`, `<ACRO3>` ...) reliably when included in the glossary.

The glossary did **not** save:

- `Replit` (rendered as `PocketOS` in the DE pass) — a public third-party brand name with low Whisper prior.
- A small-town proper noun with low Whisper prior (rendered as a phonetic neighbor).
- A compound acronym with a one-letter delta (e.g. `<ACRO-A> bonus` rendered as `<ACRO-B> bonus`).

Mitigation: keep a post-processing list of `(wrong, right)` pairs and apply with a sed-style replacement after Whisper. For high-stakes proper nouns, listen to the audio at the timestamp before quoting.

### Audio is the primary evidence; the transcript is a working aid

For any quotation that may be presented externally (lawyer, court, HR escalation):

1. **Cite the audio file + timestamp**, not just the transcript line.
2. Keep the original `.wav` (or `.mp4`) accessible — it is the legally citable artefact under § 286 ZPO (free evidence assessment in German civil law).
3. The transcript is a search aid and a draft, never the final source.
4. If you must quote in writing, use the focus-verified text and add a footnote: *"Verified against audio at [HH:MM:SS] in [filename]; full Whisper passes archived at [path]"*.

### Cross-stage consistency: bulk fixes must not overwrite focus readings

When the master SRT is large enough to need a *bulk* correction pass (a regex / sed sweep that fixes systemic Whisper errors like `CSF`→`CSA`, `BFE`→`PFE`, `middle of the tree`→`middle of the truth`), the bulk pass **operates on a different signal** than the focus pass:

- **Focus pass** sees the audio and picks the acoustically correct token.
- **Bulk pass** sees only text and picks the grammatically nearest token.

When these disagree, the bulk pass silently wins because it runs last. The result is a master SRT that contradicts its own verification table.

**Mitigation pattern:**

1. Maintain a verification table for every focus passage you have validated (passage, timestamp, focus-pass output, decision).
2. Before committing a bulk pass, list the regex patterns it will touch.
3. Cross-check each pattern against the verification table: does the bulk replacement match the focus reading?
4. After the bulk pass, `grep` the master SRT for the focus-verified phrase fragments. If the surrounding subject differs from the verification table, the bulk pass introduced a regression — revert that specific replacement.
5. The verification table is the source of truth for verbatim quotes. The master SRT is a derivative artefact.

**Real-world failure mode (anonymized):**

| Stage | Output | Source |
|---|---|---|
| Whisper v1 (default) | `<SubjectA>, will you be required, as a manager, to take Action X` | full pass, language drift made the statement a question |
| Whisper v2 (glossary, no-condition) | `the life question will be required as a manager to take Action X` | full pass, single-syllable subject hallucinated |
| Focus pass on the same passage (`focus_passage_a`, beam=10, no-VAD, glossary) | `<SubjectA> will be required as a manager to take Action X` | acoustically verified |
| **Bulk regex pass** on master SRT | `flagged with a <Term>. **I** will be required as a manager` | mechanical resolution of the artefact, **disagrees with the focus pass** |
| Reviewer pushback (days later) | *"<PersonA> said <SubjectA>, as the manager, would have to do that — not <PersonA>"* | domain knowledge re-asserted the focus reading |
| Final master SRT | `flagged with a <Term>. **<SubjectA>** will be required as a manager` | focus-verified subject restored |

The bulk pass had survived multiple downstream commits before a reviewer caught the regression. A separate verification table (a meeting summary document) had the focus reading on record the entire time, but no automated check enforced consistency between the table and the master SRT.

**Lesson:** treat any mechanical resolution of a Whisper subject-phrase hallucination as a *hypothesis*, not a fix. Mark such replacements explicitly in the commit message (`mechanical resolution, requires focus-pass cross-check`) so a later reviewer can audit them.

## `transcribe.py`

```python
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
    p.add_argument("--language", default=None)
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
            subs.append(srt.Subtitle(
                index=i,
                start=dt.timedelta(seconds=s.start),
                end=dt.timedelta(seconds=s.end),
                content=text,
            ))
            if i % 25 == 0:
                print(f"  segment {i}: {s.end:8.1f}s  {text[:80]}", flush=True)

    srt_path.write_text(srt.compose(subs), encoding="utf-8")
    json_path.write_text(
        json.dumps({
            "language": info.language,
            "language_probability": info.language_probability,
            "duration": info.duration,
            "segments": rows,
        }, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"OK. Wrote:\n  {txt_path}\n  {srt_path}\n  {json_path}")


if __name__ == "__main__":
    main()
```

## `diarize.py`

```python
"""Speaker diarization with pyannote/speaker-diarization-3.1.

Merges speaker turns into Whisper segments produced by transcribe.py.
Bypasses torchcodec by pre-loading audio with torchaudio.

Outputs <base>.rttm, <base>.diarized.{json,srt,txt}.
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
    p.add_argument("--json", type=Path, required=True, help="transcribe.py output")
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

    base = args.json.with_suffix("")
    rttm_path = Path(str(base) + ".rttm")
    with rttm_path.open("w", encoding="utf-8") as f:
        diarization.write_rttm(f)

    turns: list[tuple[float, float, str]] = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        turns.append((turn.start, turn.end, speaker))

    data = json.loads(args.json.read_text(encoding="utf-8"))
    segments = data["segments"]
    assign_speakers(segments, turns)

    out_json = Path(str(base) + ".diarized.json")
    out_srt = Path(str(base) + ".diarized.srt")
    out_txt = Path(str(base) + ".diarized.txt")

    out_json.write_text(
        json.dumps({**data,
                    "speaker_turns": [[s, e, sp] for s, e, sp in turns],
                    "segments": segments},
                   ensure_ascii=False, indent=2),
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

    speakers: dict[str, float] = defaultdict(float)
    for s in segments:
        speakers[s["speaker"]] += s["end"] - s["start"]
    print("\nSpeaker time (s):")
    for spk, secs in sorted(speakers.items(), key=lambda x: -x[1]):
        print(f"  {spk:14s} {secs:8.1f}")

    print(f"\nOK. Wrote:\n  {out_json}\n  {out_srt}\n  {out_txt}")


if __name__ == "__main__":
    main()
```

## Verification

After each stage, sanity-check the artifacts before moving on.

```powershell
# Audio extraction
Get-Item '<input>.wav' | Select-Object Length, LastWriteTime

# Whisper output
$j = Get-Content '<input>.json' -Raw -Encoding UTF8 | ConvertFrom-Json
"Language: $($j.language)  prob=$([math]::Round($j.language_probability,3))"
"Duration: $([math]::Round($j.duration/60,1)) min"
"Segments: $($j.segments.Count)"

# Diarization output
Get-Content '<input>.rttm' | Select-Object -First 5
$d = Get-Content '<input>.diarized.json' -Raw -Encoding UTF8 | ConvertFrom-Json
$d.segments | Group-Object speaker | Sort-Object Count -Descending |
    Select-Object Name, Count
```

## Operator notes

- **Token hygiene**: never paste the HF token into chat or commit it. Set it once via `setx HF_TOKEN ...` or the `[Environment]::SetEnvironmentVariable(...,'User')` form.
- **Model cache**: faster-whisper and HF cache models under `%USERPROFILE%\.cache\huggingface\hub`. First run of `large-v3` downloads ~3 GB; pyannote pipeline ~100 MB.
- **VRAM**: `large-v3` float16 fits in ~6 GB; pyannote 3.1 needs ~2 GB. Both run sequentially in this pipeline so an 8 GB GPU is enough.
- **Long audio**: VAD filtering (`vad_filter=True`) is enabled by default in `transcribe.py` to skip silence; this reduces hallucinated repetitions in long meetings.
- **Mixed languages**: `large-v3` handles in-segment switching even when `--language` is fixed; only set `--language` if you want to suppress detection drift.
