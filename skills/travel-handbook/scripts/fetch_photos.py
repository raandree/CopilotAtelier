# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10.3", "requests>=2.32.4", "ruamel.yaml>=0.18", "tzdata"]
# ///
"""Fetch the trip's photos from Wikimedia Commons, crop them, and credit their authors.

For each entry in photos the script reads the file's license, author, and
license link from the Commons API (prop=imageinfo, iiprop=url|size|extmetadata,
iiextmetadatafilter=LicenseShortName|Artist|LicenseUrl), accepts only CC0,
public domain, CC BY, and CC BY-SA, downloads a large rendition (never the
original) from upload.wikimedia.org, crops it around the configured focus to
3:2 (960 x 640) or, for a banner, 8:3 (1600 x 600), and saves only its pixels
as JPEG, without EXIF, XMP, or any other metadata, which drops camera data and
GPS positions. It writes a credits table per language (credits.md,
credits.<lang>.md) with author, license link, and file page, and states that
each crop keeps the license of its original (ShareAlike where it applies).
Commons text reaches the table escaped, and a link only when it points to the
license sites or to the file's Commons page.

With --candidates it builds, for each photo_candidates subject, a numbered
contact sheet of freely licensed files (330 px thumbnails, at most 1,400 px
wide) under the cache folder, featured and quality images first, to choose
from; a file whose thumbnail fails is skipped and reported. Category queries
use gcmlimit=50 with the metadata filter: 200 with full metadata is refused
with HTTP 429.
"""
from __future__ import annotations

import html
import math
import re
import sys
from urllib.parse import quote, urlsplit

from PIL import Image, ImageDraw, ImageFont, ImageOps

sys.dont_write_bytecode = True  # an installed Skill folder must not collect __pycache__
import trip  # noqa: E402

USAGE = """examples (from the repository root):
  uv run skills/travel-handbook/scripts/fetch_photos.py handbook/trip.yaml
  uv run skills/travel-handbook/scripts/fetch_photos.py handbook/trip.yaml --candidates

stdout: "<sha256>  <path>" per output; with --candidates, each sheet and its
numbered files. stderr: refused licenses, skipped candidates, retries, and the
HTTP summary with the count of HTTP 429 answers."""

API = "https://commons.wikimedia.org/w/api.php"
METADATA = "LicenseShortName|Artist|LicenseUrl"
FEATURED = "Category:Featured pictures on Wikimedia Commons"
QUALITY = "Category:Quality images"
FREE_LICENSE = re.compile(r"^(?:CC0(?: 1\.0)?|Public domain|CC BY(?:-SA)? [1-4]\.[05](?: [A-Za-z-]{2,10})?)$",
                          re.IGNORECASE)
CREATIVE_COMMONS_HTTP = re.compile(r"^http://((?:[\w-]+\.)*creativecommons\.org)(?=/|$)",
                                   re.IGNORECASE)
LICENSE_DOMAINS = ("creativecommons.org", "wikimedia.org", "wikipedia.org")  # license link sites
FILE_PAGE_HOST = "commons.wikimedia.org"  # the only host a credits row links a file page to
UPLOAD_HOST = "upload.wikimedia.org"  # the only download host: Commons serves renditions there
LINK_SAFE = ":/%#?=&_.-~"  # kept in a Markdown link target; ( ) < > and blanks are encoded
MARKDOWN_SPECIAL = re.compile(r"[\\`*_\[\]|~<>&]")  # escaped in a cell: no markup, tag, or entity
HTML_SPECIAL = {"&": "&amp;", "<": "&lt;", ">": "&gt;"}
GALLERY_SIZE = (960, 640)  # 3:2, sharp across a phone screen or a page column
BANNER_SIZE = (1600, 600)  # 8:3, a banner across the top of a page
GALLERY_SOURCE = 1280  # px wide rendition to download for a gallery crop: room to crop 960
BANNER_SOURCE = 1920  # px wide rendition for a banner crop: room to crop 1600
JPEG_QUALITY = 82  # visually clean at about a third of the size of quality 95
COMMONS_BACKOFF = 20.0  # seconds, times the attempt: Commons' HTTP 429 clears within minutes
COMMONS_PAUSE = 2.0  # seconds between downloads: Commons throttles bursts
CATEGORY_BATCH = 50  # files per query: gcmlimit=200 with full metadata draws HTTP 429
THUMB_WIDTH = 330  # px per thumbnail: four of them and their gaps fill a 1,400 px sheet
THUMB_HEIGHT = 248  # px: a 4:3 cell; other shapes are letterboxed inside it
SHEET_MAX_WIDTH = 1400  # px: a contact sheet one screen wide, legible without zooming
SHEET_GAP = 16  # px between thumbnails and around the sheet
BADGE = 34  # px square of the number badge in a thumbnail's corner
BADGE_FONT = 20  # px text size of the badge number


class PhotoRefused(trip.TripError):
    """A configured photo is missing on Commons or has a license outside the free list."""


def plain_text(value: str) -> str:
    """Strip HTML tags and entities from a Commons metadata field.

    The result is plain text, not Markdown: a decoded &lt;img&gt; is a tag again,
    so the credits table escapes every value through _cell.
    """
    text = re.sub(r"<[^>]+>", "", value or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def https_license_url(url: str) -> str:
    """Use https for Creative Commons links; Commons returns http for CC0."""
    return CREATIVE_COMMONS_HTTP.sub(r"https://\1", (url or "").strip())


def _https_host(url: object) -> str | None:
    """The host of a plain https URL without user name, port, blank, or backslash; else None."""
    if not isinstance(url, str) or not url.strip():
        return None
    text = url.strip()
    if "\\" in text or any(char.isspace() or not char.isprintable() for char in text):
        return None
    try:
        parts = urlsplit(text)
    except ValueError:
        return None
    host = parts.hostname or ""
    return host if host and parts.scheme == "https" and parts.netloc.lower() == host else None


def license_link(url: str) -> str | None:
    """The license URL as a Markdown link target, when it is https on a license site."""
    host = _https_host(url)
    if host is None or not any(host == domain or host.endswith("." + domain)
                               for domain in LICENSE_DOMAINS):
        return None
    return quote(url.strip(), safe=LINK_SAFE)


def file_page_link(url: str) -> str | None:
    """The file page URL as a Markdown link target, when it is https on Commons."""
    return quote(url.strip(), safe=LINK_SAFE) if _https_host(url) == FILE_PAGE_HOST else None


def is_free_license(name: str) -> bool:
    """True for CC0, public domain, CC BY, and CC BY-SA; false for NC, ND, GFDL, and others."""
    return FREE_LICENSE.match(plain_text(name)) is not None


def describe(page: dict) -> dict:
    """The fields of a Commons imageinfo page that the credits and the crop need."""
    info = page["imageinfo"][0]
    meta = info.get("extmetadata") or {}

    def field(key: str) -> str:
        return plain_text((meta.get(key) or {}).get("value", ""))

    license_name = field("LicenseShortName")
    return {
        "file": page["title"],
        "page": info.get("descriptionurl", ""),
        "source": info.get("thumburl") or "",  # never the original: it may hold 100 megapixels
        "author": field("Artist") or "unknown",
        "license": license_name,
        "license_url": https_license_url((meta.get("LicenseUrl") or {}).get("value", "")),
        "pixels": int(info.get("width", 0)) * int(info.get("height", 0)),
        "free": is_free_license(license_name),
    }


def _query(width: int) -> dict:
    return {"action": "query", "format": "json", "formatversion": 2, "prop": "imageinfo",
            "iiprop": "url|size|extmetadata", "iiextmetadatafilter": METADATA,
            "iiurlwidth": width}


def commons_metadata(http: trip.Http, title: str, width: int) -> dict:
    answer = http.get_json(API, {**_query(width), "titles": title}, backoff=COMMONS_BACKOFF)
    pages = (answer.get("query") or {}).get("pages") or []
    if not pages or pages[0].get("missing") or not pages[0].get("imageinfo"):
        raise PhotoRefused(f"{title}: no such file on Wikimedia Commons")
    return describe(pages[0])


def crop(image: Image.Image, size: tuple[int, int], focus: tuple[float, float]) -> Image.Image:
    """Crop to the target aspect ratio around the focus (0 = left/top, 1 = right/bottom)."""
    target = size[0] / size[1]
    width, height = image.size
    if width / height > target:
        new_width = round(height * target)
        left = round((width - new_width) * focus[0])
        box = (left, 0, left + new_width, height)
    else:
        new_height = round(width / target)
        top = round((height - new_height) * focus[1])
        box = (0, top, width, top + new_height)
    return image.crop(box).resize(size, Image.Resampling.LANCZOS)


def save_jpeg(image: Image.Image, path) -> str:
    """Save only the pixels, with no EXIF, XMP, or comment (no GPS position); return the SHA-256.

    Copying info would carry metadata along: Pillow 11.0 wrote a source's XMP, and
    every version writes its JPEG comment, so the saved image is rebuilt from raw pixels.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb = image.convert("RGB")
    clean = Image.frombytes("RGB", rgb.size, rgb.tobytes())
    clean.save(path, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
    return trip.sha256_file(path)


def _download(http: trip.Http, url: str) -> Image.Image:
    if not url:
        raise PhotoRefused("Commons offers no rendition of the requested width")
    if _https_host(url) != UPLOAD_HOST:
        raise PhotoRefused(f"{url}: photos are downloaded only from https://{UPLOAD_HOST}")
    data = http.get(url, backoff=COMMONS_BACKOFF, pause=COMMONS_PAUSE, check=trip.image_answer)
    try:
        with trip.open_image(data) as image:
            # Turn the pixels upright before the orientation tag is dropped with the EXIF.
            return ImageOps.exif_transpose(image).convert("RGB")
    except Exception as error:  # Pillow raises several types for an image it cannot decode
        raise PhotoRefused(f"{url}: cannot decode the image ({error})") from None


def _cell(text: str) -> str:
    """Text for a table cell: one line, with Markdown and HTML specials escaped."""
    line = " ".join(str(text).split())
    return MARKDOWN_SPECIAL.sub(lambda match: HTML_SPECIAL.get(match[0], "\\" + match[0]), line)


def credits_document(config: trip.Trip, lang: str, entries: list[tuple[trip.Photo, dict]]) -> str:
    header = [config.text(lang, key) for key in ("credits_photo", "credits_author",
                                                 "credits_license", "credits_file")]
    lines = [f"# {config.text(lang, 'credits_title')}", "", config.text(lang, "credits_note"), "",
             "| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    for photo, info in entries:
        license_url = license_link(info["license_url"])
        license_text = (f"[{_cell(info['license'])}]({license_url})" if license_url
                        else _cell(info["license"]))
        page = file_page_link(info["page"])
        file_text = f"[{_cell(info['file'])}]({page})" if page else _cell(info["file"])
        lines.append(f"| {_cell(photo.caption[lang])} (`{photo.name}.jpg`) | "
                     f"{_cell(info['author'])} | {license_text} | {file_text} |")
    return "\n".join(lines) + "\n"


def fetch(config: trip.Trip, http: trip.Http) -> int:
    if not config.photos:
        trip.log("no photos configured; nothing to fetch")
        return trip.EXIT_OK
    outputs, entries, refused = [], [], []
    for photo in config.photos:
        try:
            info = commons_metadata(http, photo.file, BANNER_SOURCE if photo.banner else GALLERY_SOURCE)
        except PhotoRefused as error:
            refused.append(f"photos: {photo.name}: {error}")
            continue
        if not info["free"]:
            refused.append(f"photos: {photo.name}: {photo.file} has the license "
                           f"{info['license'] or 'unknown'!r}; only CC0, public domain, CC BY, "
                           "and CC BY-SA are accepted")
            continue
        try:
            source = _download(http, info["source"])
        except PhotoRefused as error:
            refused.append(f"photos: {photo.name}: {error}")
            continue
        image = crop(source, BANNER_SIZE if photo.banner else GALLERY_SIZE, photo.focus)
        path = config.paths.photos / f"{photo.name}.jpg"
        outputs.append((path, save_jpeg(image, path)))
        entries.append((photo, info))
    for lang in config.languages:
        path = config.output(config.paths.photos, "credits", lang, ".md")
        outputs.append((path, trip.write_text(path, credits_document(config, lang, entries))))
    for path, digest in outputs:
        trip.print_output(path, digest)
    for problem in refused:
        trip.log(problem)
    return trip.EXIT_CHECK if refused else trip.EXIT_OK


def quality_ranks(http: trip.Http, titles: list[str]) -> dict[str, int]:
    """2 for featured pictures, 1 for quality images, 0 otherwise.

    Searching for incategory:"Quality_images" returns nothing, so the ranking
    asks for the two categories of the candidate files instead.
    """
    ranks: dict[str, int] = {}
    for start in range(0, len(titles), CATEGORY_BATCH):
        answer = http.get_json(API, {
            "action": "query", "format": "json", "formatversion": 2, "prop": "categories",
            "titles": "|".join(titles[start:start + CATEGORY_BATCH]),
            "clcategories": f"{QUALITY}|{FEATURED}", "cllimit": "max",
        }, backoff=COMMONS_BACKOFF)
        for page in (answer.get("query") or {}).get("pages") or []:
            names = {category.get("title") for category in page.get("categories") or []}
            ranks[page.get("title", "")] = 2 if FEATURED in names else 1 if QUALITY in names else 0
    return ranks


def contact_sheet(thumbs: list[Image.Image]) -> Image.Image:
    """Numbered thumbnails in rows of four, at most SHEET_MAX_WIDTH pixels wide."""
    columns = max(1, (SHEET_MAX_WIDTH - SHEET_GAP) // (THUMB_WIDTH + SHEET_GAP))
    rows = max(1, math.ceil(len(thumbs) / columns))
    sheet = Image.new("RGB", (columns * THUMB_WIDTH + (columns + 1) * SHEET_GAP,
                              rows * THUMB_HEIGHT + (rows + 1) * SHEET_GAP), "white")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=BADGE_FONT)
    for index, thumb in enumerate(thumbs):
        column, row = index % columns, index // columns
        x = SHEET_GAP + column * (THUMB_WIDTH + SHEET_GAP)
        y = SHEET_GAP + row * (THUMB_HEIGHT + SHEET_GAP)
        sheet.paste(thumb, (x + (THUMB_WIDTH - thumb.width) // 2,
                            y + (THUMB_HEIGHT - thumb.height) // 2))
        draw.rectangle((x, y, x + BADGE, y + BADGE), fill="black")
        draw.text((x + BADGE / 2, y + BADGE / 2), str(index + 1), fill="white", font=font,
                  anchor="mm")
    return sheet


def candidates(config: trip.Trip, http: trip.Http, subject: str | None) -> int:
    chosen = [item for item in config.photo_candidates if subject in (None, item.subject)]
    if not chosen:
        raise trip.ConfigError([f"--subject: no photo_candidates entry named {subject!r}"
                                if subject else "photo_candidates: no subjects to search"])
    folder = config.paths.cache / "candidates"
    for item in chosen:
        params = _query(THUMB_WIDTH)
        if item.category:
            params.update({"generator": "categorymembers", "gcmtitle": item.category,
                           "gcmtype": "file", "gcmlimit": CATEGORY_BATCH})
        else:
            params.update({"generator": "search", "gsrsearch": item.search,
                           "gsrnamespace": 6, "gsrlimit": CATEGORY_BATCH})  # 6: the File namespace
        answer = http.get_json(API, params, backoff=COMMONS_BACKOFF)
        pages = [page for page in (answer.get("query") or {}).get("pages") or []
                 if page.get("imageinfo")]
        found = [describe(page) for page in pages]
        free = [info for info in found if info["free"]]
        ranks = quality_ranks(http, [info["file"] for info in free])
        free.sort(key=lambda info: (-ranks.get(info["file"], 0), -info["pixels"], info["file"]))
        picked = free[:item.limit]
        thumbs, shown, skipped = [], [], 0
        for info in picked:
            try:
                thumb = _download(http, info["source"])
            except (PhotoRefused, trip.NetworkError) as error:
                if http.offline and isinstance(error, trip.NetworkError):
                    raise  # --offline promises exit code 3 when a cached copy is missing
                trip.log(f"{item.subject}: {info['file']} skipped: {error}")
                skipped += 1
                continue
            thumb.thumbnail((THUMB_WIDTH, THUMB_HEIGHT), Image.Resampling.LANCZOS)
            thumbs.append(thumb)
            shown.append(info)
        path = folder / f"{item.subject}.jpg"
        save_jpeg(contact_sheet(thumbs), path)
        note = f"; {skipped} skipped, reasons on stderr" if skipped else ""
        print(f"{item.subject}: {trip.display_path(path)} ({len(shown)} shown; "
              f"{len(found) - len(free)} of {len(found)} refused for their license{note})")
        for number, info in enumerate(shown, start=1):
            tag = {2: "  featured", 1: "  quality"}.get(ranks.get(info["file"], 0), "")
            print(f"  {number:>2}  {info['file']}  {info['license']}{tag}")
    return trip.EXIT_OK


def main(argv: list[str] | None = None) -> int:
    trip.configure_console()
    parser = trip.argument_parser(__doc__.split("\n")[0], USAGE)
    parser.add_argument("config", help="trip configuration (YAML); paths are relative to it")
    parser.add_argument("--candidates", action="store_true",
                        help="build numbered contact sheets for photo_candidates instead")
    parser.add_argument("--subject", help="with --candidates: only this subject")
    parser.add_argument("--offline", action="store_true",
                        help="use cached downloads only; fail with exit code 3 when one is missing")
    args = parser.parse_args(argv)
    if args.subject and not args.candidates:
        parser.error("--subject needs --candidates")
    return trip.run(args.config, args.offline,
                    lambda config, http: (candidates(config, http, args.subject)
                                          if args.candidates else fetch(config, http)))


if __name__ == "__main__":
    raise SystemExit(main())
