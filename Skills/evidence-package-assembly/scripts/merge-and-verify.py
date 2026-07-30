"""Merge a cover sheet and source documents into one evidence package and verify it.

Usage:  uv run --with pypdf --with pymupdf python merge-and-verify.py manifest.json

Manifest:
    {
      "cover": "C:/Temp/cover.pdf",
      "out":   "output/anlage-11.pdf",
      "title": "Anlage 11 - Praesenzbelege",
      "parts": [
        {"id": "11.1", "file": "input/Targobank 2022-01.pdf", "skip": [8]},
        {"id": "11.2", "file": "input/ING 2022-03.pdf"}
      ]
    }

`cover` is optional; omit it for a package small enough to be described by the
covering letter's schedule of attachments. `skip` lists source page numbers
(1-based) to omit. Omissions are printed so they stay visible in the build log.
Page ranges are printed so the cover can be filled from this output rather than
by hand.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

import pymupdf
from pypdf import PdfReader, PdfWriter

sys.stdout.reconfigure(encoding="utf-8")

SEITENZAHL = re.compile(r"Seite\s*(\d+)\s*(?:von|/)\s*(\d+)", re.IGNORECASE)


def build(manifest: dict) -> list[tuple[str, int, int]]:
    out = pathlib.Path(manifest["out"])
    writer = PdfWriter()

    if cover := manifest.get("cover"):
        for page in PdfReader(cover).pages:
            writer.add_page(page)
        print(f"Deckblatt: Seiten 1-{len(writer.pages)}")
    else:
        print("Kein Deckblatt")
    pos = len(writer.pages)

    bereiche: list[tuple[str, int, int]] = []
    for teil in manifest["parts"]:
        quelle = pathlib.Path(teil["file"])
        if not quelle.exists():
            raise SystemExit(f"FEHLT: {quelle}")
        skip = set(teil.get("skip", []))
        reader = PdfReader(quelle)
        start = pos + 1
        for i, page in enumerate(reader.pages, 1):
            if i in skip:
                continue
            writer.add_page(page)
            pos += 1
        bereiche.append((teil["id"], start, pos))
        hinweis = f"  [ohne Quellseite {sorted(skip)}]" if skip else ""
        print(f"{teil['id']:6s} Seiten {start}-{pos}  ({pos - start + 1} S.){hinweis}  {quelle.name}")

    if title := manifest.get("title"):
        writer.add_metadata({"/Title": title})

    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wb") as fh:
        writer.write(fh)
    return bereiche


def verify(manifest: dict, bereiche: list[tuple[str, int, int]]) -> int:
    out = pathlib.Path(manifest["out"])
    doc = pymupdf.open(out)
    print(f"\nErgebnis: {out.name}  {doc.page_count} Seiten  {out.stat().st_size / 1024:.0f} KB")

    fehler = 0

    ohne_text = [i + 1 for i, page in enumerate(doc) if not page.get_text().strip()]
    print(f"Seiten ohne Textebene: {ohne_text if ohne_text else 'keine'}")

    print("\nQuelleigene Seitenzaehlung:")
    for teil_id, a, b in bereiche:
        gefunden: list[int] = []
        gesamt: set[int] = set()
        for i in range(a, b + 1):
            text = re.sub(r"\s+", " ", doc[i - 1].get_text())
            for treffer in SEITENZAHL.finditer(text):
                gefunden.append(int(treffer.group(1)))
                gesamt.add(int(treffer.group(2)))
        if not gesamt:
            print(f"  {teil_id:6s} keine Zaehlung im Dokument")
            continue
        n = max(gesamt)
        fehlend = sorted(set(range(1, n + 1)) - set(gefunden))
        # Deckblattseiten eines Auszugs tragen haeufig keine Nummer; nur Luecken ab 2 sind kritisch.
        kritisch = [s for s in fehlend if s > 1]
        if kritisch:
            fehler += 1
            print(f"  {teil_id:6s} LUECKE: {kritisch} von {n} fehlen")
        else:
            hinweis = " (Seite 1 unnummeriert)" if fehlend else ""
            print(f"  {teil_id:6s} vollstaendig 1-{n}{hinweis}")

    return fehler


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    daten = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    ergebnis = verify(daten, build(daten))
    if ergebnis:
        raise SystemExit(f"\n{ergebnis} Teilanlage(n) mit Luecke in der Seitenzaehlung.")
    print("\nPruefung bestanden.")
