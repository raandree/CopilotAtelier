# Transcribe a section of a 16 kHz mono PCM WAV with faster-whisper.
from __future__ import annotations
import argparse, datetime as dt, json, wave
from pathlib import Path
import numpy as np
import srt
from faster_whisper import WhisperModel


def read_wav_segment(path: Path, start_s: float, end_s: float | None) -> tuple[np.ndarray, int]:
    with wave.open(str(path), 'rb') as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise SystemExit('Expecting mono 16-bit PCM WAV')
        sr = w.getframerate()
        total = w.getnframes()
        start_f = int(start_s * sr)
        end_f = total if end_s is None else int(end_s * sr)
        if start_f < 0 or end_f > total or start_f >= end_f:
            raise SystemExit(f'Invalid range: start={start_s}s end={end_s}s total={total/sr:.2f}s')
        w.setpos(start_f)
        raw = w.readframes(end_f - start_f)
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return samples, sr


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('audio', type=Path)
    p.add_argument('--start', type=float, default=0.0, help='start in seconds')
    p.add_argument('--end', type=float, default=None, help='end in seconds (default: file end)')
    p.add_argument('--language', default='en')
    p.add_argument('--model', default='large-v3')
    p.add_argument('--compute-type', default='float16')
    p.add_argument('--beam-size', type=int, default=5)
    p.add_argument('--suffix', default='_en', help='suffix appended to output basenames')
    p.add_argument('--initial-prompt-file', type=Path, default=None,
                   help='UTF-8 text file whose content is used as Whisper initial_prompt (glossary)')
    p.add_argument('--no-condition', action='store_true',
                   help='disable condition_on_previous_text (loop-mitigation; recommended for long segments)')
    args = p.parse_args()

    samples, sr = read_wav_segment(args.audio, args.start, args.end)
    if sr != 16000:
        raise SystemExit(f'Sample rate must be 16000, got {sr}')
    base = args.audio.with_name(args.audio.stem + args.suffix)

    initial_prompt = None
    if args.initial_prompt_file is not None:
        initial_prompt = args.initial_prompt_file.read_text(encoding='utf-8').strip()

    print(f'Loading model {args.model} on cuda/{args.compute_type} ...', flush=True)
    model = WhisperModel(args.model, device='cuda', compute_type=args.compute_type)

    duration = len(samples) / sr
    print(f'Transcribing offset={args.start:.1f}s segment_len={duration:.1f}s lang={args.language} ...', flush=True)
    if initial_prompt:
        print(f'  initial_prompt: {initial_prompt[:100]}...', flush=True)
    if args.no_condition:
        print('  condition_on_previous_text=False (loop-mitigation)', flush=True)

    transcribe_kwargs: dict = dict(
        language=args.language,
        vad_filter=True,
        beam_size=args.beam_size,
    )
    if initial_prompt:
        transcribe_kwargs['initial_prompt'] = initial_prompt
    if args.no_condition:
        transcribe_kwargs['condition_on_previous_text'] = False

    segments, info = model.transcribe(samples, **transcribe_kwargs)

    txt_path = base.with_suffix('.txt')
    srt_path = base.with_suffix('.srt')
    json_path = base.with_suffix('.json')

    rows: list[dict] = []
    subs: list[srt.Subtitle] = []
    offset = args.start
    with txt_path.open('w', encoding='utf-8') as f_txt:
        for i, s in enumerate(segments, start=1):
            text = s.text.strip()
            f_txt.write(text + '\n')
            abs_start = s.start + offset
            abs_end = s.end + offset
            rows.append({'start': abs_start, 'end': abs_end, 'text': text})
            subs.append(srt.Subtitle(
                index=i,
                start=dt.timedelta(seconds=abs_start),
                end=dt.timedelta(seconds=abs_end),
                content=text,
            ))
            if i % 25 == 0:
                print(f'  segment {i}: {abs_end:8.1f}s  {text[:80]}', flush=True)

    srt_path.write_text(srt.compose(subs), encoding='utf-8')
    json_path.write_text(json.dumps({
        'language': info.language,
        'language_probability': info.language_probability,
        'duration': info.duration,
        'offset': args.start,
        'segments': rows,
    }, ensure_ascii=False, indent=2), encoding='utf-8')

    print(f'OK. Wrote:\n  {txt_path}\n  {srt_path}\n  {json_path}')


if __name__ == '__main__':
    main()
