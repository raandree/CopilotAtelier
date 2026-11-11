"""Synthetic stand-ins for every network service the travel-handbook scripts use.

The fake session answers tile, Nominatim, Open-Meteo, Wikimedia Commons, and
Google My Maps requests with invented data around 45.9 N, 7.1 E, and records
each request so a test can count them. No answer comes from the real network.
"""
from __future__ import annotations

import io
import json
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

FIXTURES = Path(__file__).resolve().parent / "fixtures"

# What the fake elevation API answers for every point, in metres.
SYNTHETIC_DEM = 2113.0

MINIMAL = """\
languages: [en]
user_agent: "travel-handbook-tests/1.0 (tests@example.org)"
timezone: Europe/Zurich
places:
  alpha:
    name: Alpha Village
    lat: 45.9
    lon: 7.1
    elevation: 1450
    source: Synthetic test data
nights:
  - {date: 2027-07-01, place: alpha}
"""

# A hexagon standing in for a country outline, as Nominatim returns it.
OUTLINE = {
    "type": "Polygon",
    "coordinates": [[[6.0, 45.8], [6.8, 45.6], [7.9, 45.7], [8.3, 46.2],
                     [7.6, 46.6], [6.4, 46.5], [6.0, 45.8]]],
}

CANDIDATES = ["File:Candidate 1.jpg", "File:Candidate 2.jpg", "File:Candidate 3.jpg",
              "File:Candidate 4 nonfree.jpg", "File:Candidate 5.jpg", "File:Candidate 6.jpg"]
FEATURED = "File:Candidate 5.jpg"
QUALITY = "File:Candidate 3.jpg"
ARTIST_HTML = ('<a href="//commons.wikimedia.org/wiki/User:Example" '
               'title="User:Example">Example &amp; Co</a>')


class FakeResponse:
    def __init__(self, status_code=200, content=b"", headers=None):
        self.status_code = status_code
        self.content = content
        self.headers = dict(headers or {})
        self.closed = False

    def iter_content(self, chunk_size=1):
        """Hand out the body in chunks, as requests does for stream=True."""
        for start in range(0, len(self.content), chunk_size):
            yield self.content[start:start + chunk_size]

    def close(self):
        self.closed = True


class FakeSession:
    """Answer GET requests through a handler and record each URL with its headers."""

    def __init__(self, handler):
        self.handler = handler
        self.calls = []

    def get(self, url, headers=None, timeout=None, stream=False):
        self.calls.append((url, dict(headers or {})))
        result = self.handler(url)
        if isinstance(result, FakeResponse):
            return result
        if isinstance(result, (bytes, bytearray)):
            return FakeResponse(200, bytes(result))
        return FakeResponse(200, json.dumps(result).encode("utf-8"))

    def urls(self, fragment=""):
        return [url for url, _ in self.calls if fragment in url]


def sequence(*responses):
    """Return a handler that answers with the given responses in order."""
    queue = list(responses)

    def handler(url):
        return queue.pop(0)

    return handler


class FakeClock:
    """Record waits instead of sleeping; time moves only when the code waits."""

    def __init__(self):
        self.slept = []
        self.current = datetime(2030, 1, 1, tzinfo=timezone.utc)

    def sleep(self, seconds):
        self.slept.append(seconds)
        self.current += timedelta(seconds=seconds)

    def now(self):
        return self.current


def png(image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return buffer.getvalue()


def jpeg_with_exif(size=(1280, 960), **options) -> bytes:
    """A two-colour JPEG (orange top, blue bottom) carrying camera and GPS EXIF tags."""
    from PIL import Image, ImageDraw

    image = Image.new("RGB", size, (230, 126, 34))
    ImageDraw.Draw(image).rectangle((0, size[1] // 2, size[0], size[1]), fill=(41, 128, 185))
    exif = Image.Exif()
    exif[0x010F] = "Synthetic camera"
    exif[0x8825] = {1: "N", 2: (45.0, 54.0, 0.0), 3: "E", 4: (7.0, 6.0, 0.0)}
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", exif=exif, **options)
    return buffer.getvalue()


XMP_GPS = (b'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
           b'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description '
           b'xmlns:exif="http://ns.adobe.com/exif/1.0/" exif:GPSLatitude="45,54.0N" '
           b'exif:GPSLongitude="7,6.0E"/></rdf:RDF></x:xmpmeta>')


def jpeg_with_metadata(size=(1280, 960)) -> bytes:
    """jpeg_with_exif plus a JPEG comment and an XMP packet with a second GPS position."""
    data = jpeg_with_exif(size, comment=b"Synthetic comment")
    payload = b"http://ns.adobe.com/xap/1.0/\x00" + XMP_GPS
    segment = b"\xff\xe1" + (len(payload) + 2).to_bytes(2, "big") + payload  # APP1 and length
    return data[:2] + segment + data[2:]  # right after the start-of-image marker


def tile(path: str) -> bytes:
    from PIL import Image, ImageDraw

    z, x, y = (int(part) for part in path.strip("/").removesuffix(".png").split("/"))
    image = Image.new("RGB", (256, 256), (200 + x % 40, 210 + y % 30, 190 + z % 50))
    draw = ImageDraw.Draw(image)
    draw.line((0, 0, 255, 255), fill=(120, 140, 120), width=3)
    draw.rectangle((0, 0, 255, 255), outline=(150, 150, 150))
    return png(image)


def era5(query: dict) -> dict:
    start = date.fromisoformat(query["start_date"])
    end = date.fromisoformat(query["end_date"])
    elevation = float(query["elevation"])
    days = [start + timedelta(days=n) for n in range((end - start).days + 1)]
    base = 24.0 - elevation * 0.0065
    tmax = [round(base + day.day % 4 - day.year % 3, 1) for day in days]
    tmin = [round(high - 11 - day.day % 3, 1) for high, day in zip(tmax, days, strict=True)]
    return {"daily": {"time": [day.isoformat() for day in days],
                      "temperature_2m_max": tmax, "temperature_2m_min": tmin}}


def commons_page(title: str, width: int) -> dict:
    lowered = title.lower()
    if "nonfree" in lowered:
        name, url = "CC BY-NC-SA 2.0", "https://creativecommons.org/licenses/by-nc-sa/2.0"
    elif "zero" in lowered:
        name, url = "CC0", "http://creativecommons.org/publicdomain/zero/1.0/deed.en"
    else:
        name, url = "CC BY-SA 4.0", "http://creativecommons.org/licenses/by-sa/4.0"
    stem = title.removeprefix("File:").replace(" ", "_")
    extra = sum(map(ord, title)) % 7
    return {"title": title, "imageinfo": [{
        "url": f"https://upload.wikimedia.org/wikipedia/commons/{stem}",
        "thumburl": f"https://upload.wikimedia.org/wikipedia/commons/thumb/{stem}?w={width}",
        "descriptionurl": f"https://commons.wikimedia.org/wiki/{title.replace(' ', '_')}",
        "width": 4000 + 100 * extra,
        "height": 3000,
        "extmetadata": {
            "LicenseShortName": {"value": name},
            "Artist": {"value": ARTIST_HTML},
            "LicenseUrl": {"value": url},
        },
    }]}


def commons(query: dict) -> dict:
    if query.get("generator") in ("categorymembers", "search"):
        width = int(query.get("iiurlwidth", 330))
        return {"query": {"pages": [commons_page(title, width) for title in CANDIDATES]}}
    if query.get("prop") == "categories":
        pages = []
        for title in query["titles"].split("|"):
            page = {"title": title}
            if title == FEATURED:
                page["categories"] = [{"ns": 14, "title":
                                       "Category:Featured pictures on Wikimedia Commons"}]
            if title == QUALITY:
                page["categories"] = [{"ns": 14, "title": "Category:Quality images"}]
            pages.append(page)
        return {"query": {"pages": pages}}
    if query.get("prop") == "imageinfo":
        title = query["titles"]
        if "missing" in title.lower():
            return {"query": {"pages": [{"title": title, "missing": True}]}}
        return {"query": {"pages": [commons_page(title, int(query.get("iiurlwidth", 1280)))]}}
    raise AssertionError(f"unexpected Commons query {query}")


class SyntheticWeb:
    """A fake internet: tile server, Nominatim, Open-Meteo, Commons, and My Maps."""

    def __init__(self):
        self.hits = Counter()
        self.queued = []
        self.session = FakeSession(self)

    def queue(self, fragment: str, response: FakeResponse) -> None:
        """Answer the next request whose URL contains fragment with response."""
        self.queued.append((fragment, response))

    def __call__(self, url: str):
        for index, (fragment, response) in enumerate(self.queued):
            if fragment in url:
                del self.queued[index]
                return response
        parts = urlsplit(url)
        query = {key: values[0] for key, values in parse_qs(parts.query).items()}
        host = parts.netloc
        if host.endswith(".tile.opentopomap.org"):
            self.hits["tiles"] += 1
            return tile(parts.path)
        if host == "nominatim.openstreetmap.org":
            self.hits["nominatim"] += 1
            return [{"display_name": query["country"], "geojson": OUTLINE}]
        if host == "archive-api.open-meteo.com":
            self.hits["archive"] += 1
            return era5(query)
        if host == "api.open-meteo.com":
            self.hits["elevation"] += 1
            return {"elevation": [SYNTHETIC_DEM]}
        if host == "commons.wikimedia.org":
            self.hits["commons"] += 1
            return commons(query)
        if host == "upload.wikimedia.org":
            self.hits["upload"] += 1
            width = int(query.get("w", 1280))
            return jpeg_with_exif((width, width * 3 // 4))
        if host == "www.google.com":
            self.hits["kml"] += 1
            return (FIXTURES / "segments.kml").read_bytes()
        raise AssertionError(f"unexpected URL in a test: {url}")


def labels_json(language_texts: dict, drop=(), extra=None) -> str:
    """Render a complete label set as a JSON flow mapping, which is valid YAML 1.2."""
    labels = {key: value for key, value in language_texts.items() if key not in drop}
    labels.update(extra or {})
    return json.dumps(labels)
