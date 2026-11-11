"""Wikimedia Commons photos: license filter, credits, crops without metadata, contact sheets."""
from __future__ import annotations

import io
import json
import re

import pytest
from PIL import Image

import fetch_photos
import trip
from synthetic import (FEATURED, QUALITY, FakeResponse, commons_page, jpeg_with_exif,
                       jpeg_with_metadata)

CHARLIE = "File:Charlie Lake at dawn (synthetic).jpg"
CHARLIE_QUERY = "titles=File%3ACharlie+Lake"  # only the imageinfo request of the charlie_lake photo
MARKDOWN_LINK = re.compile(r"(?<!\\)\[((?:\\.|[^\\\]])*)\]\(([^)]*)\)")


def credits_row(example_path, page) -> str:
    """The credits table row that the charlie_lake photo gets from a Commons page."""
    config = trip.load_config(example_path)
    photo = next(photo for photo in config.photos if photo.name == "charlie_lake")
    document = fetch_photos.credits_document(config, "en", [(photo, fetch_photos.describe(page))])
    rows = document.splitlines()[6:]  # title, blank, note, blank, header, separator
    assert len(rows) == 1, rows  # a line break in a value must not start a row of its own
    return rows[0]


def imageinfo_answer(page) -> FakeResponse:
    return FakeResponse(200, json.dumps({"query": {"pages": [page]}}).encode("utf-8"))


@pytest.mark.parametrize("name", ["CC0", "CC0 1.0", "Public domain", "public domain",
                                  "CC BY 2.0", "CC BY-SA 4.0", "CC BY-SA 3.0 de", "cc by-sa 2.5"])
def test_free_licenses_are_accepted(name):
    assert fetch_photos.is_free_license(name)


@pytest.mark.parametrize("name", ["CC BY-NC-SA 2.0", "CC BY-ND 4.0", "CC BY-NC 4.0", "GFDL",
                                  "All rights reserved", "Fair use", ""])
def test_other_licenses_are_refused(name):
    assert not fetch_photos.is_free_license(name)


def test_artist_html_is_stripped():
    raw = ('<a href="//commons.wikimedia.org/wiki/User:Example">Example &amp; Co</a>\n'
           ' <span>(talk)</span>')

    assert fetch_photos.plain_text(raw) == "Example & Co (talk)"


@pytest.mark.parametrize("url, expected", [
    ("http://creativecommons.org/publicdomain/zero/1.0/deed.en",
     "https://creativecommons.org/publicdomain/zero/1.0/deed.en"),
    ("https://creativecommons.org/licenses/by-sa/4.0",
     "https://creativecommons.org/licenses/by-sa/4.0"),
    ("http://www.creativecommons.org/licenses/by/2.0",
     "https://www.creativecommons.org/licenses/by/2.0"),
    ("http://example.org/license", "http://example.org/license"),
])
def test_creative_commons_links_use_https(url, expected):
    assert fetch_photos.https_license_url(url) == expected


def test_target_sizes():
    assert fetch_photos.GALLERY_SIZE == (960, 640)
    assert fetch_photos.BANNER_SIZE == (1600, 600)


@pytest.mark.parametrize("source", [(1200, 900), (900, 1400), (3000, 600)])
@pytest.mark.parametrize("size", [(960, 640), (1600, 600)])
def test_crops_have_the_target_size(source, size):
    assert fetch_photos.crop(Image.new("RGB", source), size, (0.5, 0.5)).size == size


def test_vertical_focus_chooses_the_part_kept():
    image = Image.open(io.BytesIO(jpeg_with_exif((900, 1400)))).convert("RGB")

    top = fetch_photos.crop(image, fetch_photos.BANNER_SIZE, (0.5, 0.0))
    bottom = fetch_photos.crop(image, fetch_photos.BANNER_SIZE, (0.5, 1.0))

    assert top.getpixel((800, 300))[0] > 200
    assert bottom.getpixel((800, 300))[2] > 150


def test_saved_photo_has_no_exif(tmp_path):
    source = Image.open(io.BytesIO(jpeg_with_exif()))
    assert len(source.getexif()) > 0
    out = tmp_path / "photo.jpg"

    fetch_photos.save_jpeg(fetch_photos.crop(source, fetch_photos.GALLERY_SIZE, (0.5, 0.5)), out)

    with Image.open(out) as saved:
        assert len(saved.getexif()) == 0
        assert "exif" not in saved.info


def test_saved_photo_carries_no_metadata_at_all(tmp_path):
    # Pillow 11.0 wrote a source's XMP, which can hold a GPS position, into every
    # JPEG it saved, and every version keeps a source's JPEG comment.
    source = Image.open(io.BytesIO(jpeg_with_metadata()))
    assert {"exif", "xmp", "comment"} <= set(source.info)
    out = tmp_path / "photo.jpg"

    fetch_photos.save_jpeg(fetch_photos.crop(source, fetch_photos.GALLERY_SIZE, (0.5, 0.5)), out)

    with Image.open(out) as saved:
        assert {"exif", "xmp", "comment", "icc_profile"}.isdisjoint(saved.info)
        assert len(saved.getexif()) == 0
    data = out.read_bytes()
    assert b"http://ns.adobe.com/xap/1.0/" not in data
    assert b"Synthetic" not in data


def test_credits_escape_hostile_commons_text(example_path):
    page = commons_page(CHARLIE, 1280)
    page["title"] = "File:Evil](javascript:alert(1)) <script>alert(2)</script> | cell.jpg"
    page["imageinfo"][0]["extmetadata"]["Artist"]["value"] = (
        "&lt;img src=x onerror=alert(3)&gt; [click](javascript:alert(4)) *bold* `code` ~gone~\n"
        "| injected | row |")

    row = credits_row(example_path, page)

    assert len(re.split(r"(?<!\\)\|", row)) == 6  # four cells between the outer pipes
    assert "<" not in row and ">" not in row
    assert "&lt;img src=x onerror=alert(3)&gt;" in row
    assert "&lt;script&gt;" in row
    targets = [target for _, target in MARKDOWN_LINK.findall(row)]
    assert targets == ["https://creativecommons.org/licenses/by-sa/4.0",
                       "https://commons.wikimedia.org/wiki/File:Charlie_Lake_at_dawn_%28synthetic%29.jpg"]
    for special in ("\\*bold\\*", "\\`code\\`", "\\~gone\\~", "\\[click\\]"):
        assert special in row


@pytest.mark.parametrize("url", [
    "javascript:alert(1)",
    "data:text/html,<script>alert(1)</script>",
    "http://example.org/license",
    "//creativecommons.org/licenses/by-sa/4.0",
    "https://creativecommons.org.evil.example/licenses/by-sa/4.0",
    "https://evilcreativecommons.org/licenses/by-sa/4.0",
    "https://evil.example/?creativecommons.org",
    "https://user@creativecommons.org/licenses/by-sa/4.0",
    "https://creativecommons.org:8443/licenses/by-sa/4.0",
    "https://evil.example\\@creativecommons.org/licenses/by-sa/4.0",
    "https://creativecommons.org/licenses/by-sa/4.0 onmouseover=alert(1)",
])
def test_a_license_link_off_the_license_sites_becomes_plain_text(example_path, url):
    page = commons_page(CHARLIE, 1280)
    page["imageinfo"][0]["extmetadata"]["LicenseUrl"]["value"] = url

    row = credits_row(example_path, page)

    assert "| CC BY-SA 4.0 |" in row
    assert "[CC BY-SA 4.0]" not in row


@pytest.mark.parametrize("url, target", [
    ("http://creativecommons.org/publicdomain/zero/1.0/deed.en",
     "https://creativecommons.org/publicdomain/zero/1.0/deed.en"),
    ("https://www.creativecommons.org/licenses/by-sa/4.0",
     "https://www.creativecommons.org/licenses/by-sa/4.0"),
    ("https://en.wikipedia.org/wiki/Public_domain", "https://en.wikipedia.org/wiki/Public_domain"),
    ("https://commons.wikimedia.org/wiki/Template:PD-old",
     "https://commons.wikimedia.org/wiki/Template:PD-old"),
    ("https://creativecommons.org/licenses/by/4.0)<img/src=x/onerror=alert(1)>",
     "https://creativecommons.org/licenses/by/4.0%29%3Cimg/src=x/onerror=alert%281%29%3E"),
])
def test_license_links_to_the_license_sites_stay_links(example_path, url, target):
    page = commons_page(CHARLIE, 1280)
    page["imageinfo"][0]["extmetadata"]["LicenseUrl"]["value"] = url

    row = credits_row(example_path, page)

    assert f"[CC BY-SA 4.0]({target})" in row


@pytest.mark.parametrize("url", [
    "javascript:alert(1)//commons.wikimedia.org/wiki/File:Charlie_Lake.jpg",
    "http://commons.wikimedia.org/wiki/File:Charlie_Lake_at_dawn_(synthetic).jpg",
    "https://commons.wikimedia.org.evil.example/wiki/File:Charlie_Lake.jpg",
    "https://user@commons.wikimedia.org/wiki/File:Charlie_Lake.jpg",
    "https://upload.wikimedia.org/wikipedia/commons/Charlie_Lake.jpg",
    "https://evil.example/wiki/File:Charlie_Lake.jpg",
])
def test_a_file_page_off_commons_becomes_plain_text(example_path, url):
    page = commons_page(CHARLIE, 1280)
    page["imageinfo"][0]["descriptionurl"] = url

    row = credits_row(example_path, page)

    assert row.endswith("| File:Charlie Lake at dawn (synthetic).jpg |")


def test_a_photo_without_a_rendition_is_refused_not_downloaded_in_full(example_copy, network,
                                                                       capsys):
    page = commons_page(CHARLIE, fetch_photos.GALLERY_SOURCE)
    del page["imageinfo"][0]["thumburl"]
    network.queue(CHARLIE_QUERY, imageinfo_answer(page))

    assert fetch_photos.main([str(example_copy)]) == 1

    assert "charlie_lake" in capsys.readouterr().err
    assert network.session.urls(page["imageinfo"][0]["url"]) == []
    assert (example_copy.parent / "docs" / "images" / "photos" / "banner.jpg").exists()


@pytest.mark.parametrize("thumb", [
    "https://evil.example/Charlie_Lake.jpg",
    "http://upload.wikimedia.org/wikipedia/commons/thumb/Charlie_Lake.jpg",
    "https://upload.wikimedia.org.evil.example/Charlie_Lake.jpg",
    "https://user@upload.wikimedia.org/wikipedia/commons/thumb/Charlie_Lake.jpg",
])
def test_photos_are_downloaded_only_from_upload_wikimedia(example_copy, network, capsys, thumb):
    page = commons_page(CHARLIE, fetch_photos.GALLERY_SOURCE)
    page["imageinfo"][0]["thumburl"] = thumb
    network.queue(CHARLIE_QUERY, imageinfo_answer(page))

    assert fetch_photos.main([str(example_copy)]) == 1

    assert "charlie_lake" in capsys.readouterr().err
    assert network.session.urls("Charlie_Lake.jpg") == []


def test_photos_are_cropped_and_credited(example_copy, network, capsys):
    assert fetch_photos.main([str(example_copy)]) == 0

    folder = example_copy.parent / "docs" / "images" / "photos"
    with Image.open(folder / "banner.jpg") as banner:
        assert banner.size == fetch_photos.BANNER_SIZE
    with Image.open(folder / "charlie_lake.jpg") as gallery:
        assert gallery.size == fetch_photos.GALLERY_SIZE
        assert len(gallery.getexif()) == 0
    english = (folder / "credits.md").read_text(encoding="utf-8")
    german = (folder / "credits.de.md").read_text(encoding="utf-8")
    assert "Example &amp; Co" in english
    assert "https://creativecommons.org/licenses/by-sa/4.0" in english
    assert "http://creativecommons.org" not in english
    assert "https://commons.wikimedia.org/wiki/File:" in english
    assert "ShareAlike" in english
    assert "Charliesee" in german
    imageinfo = [url for url in network.session.urls("commons.wikimedia.org") if "imageinfo" in url]
    assert imageinfo
    assert all("iiextmetadatafilter=LicenseShortName%7CArtist%7CLicenseUrl" in url
               for url in imageinfo)
    out = capsys.readouterr()
    assert re.search(r"^[0-9a-f]{64}  .*banner\.jpg$", out.out, re.M)
    assert "HTTP 429" in out.err


def test_a_configured_photo_with_a_non_free_license_fails(example_copy, network, capsys):
    text = example_copy.read_text(encoding="utf-8")
    example_copy.write_text(text.replace("Charlie Lake at dawn (synthetic)",
                                         "Charlie Lake nonfree (synthetic)"), encoding="utf-8")

    assert fetch_photos.main([str(example_copy)]) == 1
    err = capsys.readouterr().err
    assert "CC BY-NC-SA 2.0" in err
    assert "charlie_lake" in err


def test_candidates_become_numbered_contact_sheets(example_copy, network, fake_clock, capsys):
    network.queue("generator=categorymembers", FakeResponse(429))

    assert fetch_photos.main([str(example_copy), "--candidates"]) == 0

    folder = example_copy.parent / ".cache" / "travel-handbook" / "candidates"
    sheets = sorted(folder.glob("*.jpg"))
    assert [sheet.stem for sheet in sheets] == ["charlie-lake", "echo-view"]
    for sheet in sheets:
        with Image.open(sheet) as image:
            assert image.width <= fetch_photos.SHEET_MAX_WIDTH
    out, err = capsys.readouterr()
    listed = re.findall(r"^\s+\d+  (File:.+?)  ", out, re.M)
    assert listed[:2] == [FEATURED, QUALITY]
    assert "nonfree" not in out
    category = network.session.urls("generator=categorymembers")
    assert category and all("gcmlimit=50" in url and "iiextmetadatafilter=" in url
                            and f"iiurlwidth={fetch_photos.THUMB_WIDTH}" in url
                            for url in category)
    assert fetch_photos.COMMONS_BACKOFF in fake_clock.slept
    assert fetch_photos.COMMONS_PAUSE in fake_clock.slept
    assert "1 HTTP 429" in err


def test_a_failing_candidate_is_skipped_and_reported(example_copy, network, capsys):
    for _ in range(2):  # both subjects show the same synthetic files
        network.queue("Candidate_2.jpg", FakeResponse(404))

    assert fetch_photos.main([str(example_copy), "--candidates"]) == 0

    out, err = capsys.readouterr()
    folder = example_copy.parent / ".cache" / "travel-handbook" / "candidates"
    assert sorted(sheet.stem for sheet in folder.glob("*.jpg")) == ["charlie-lake", "echo-view"]
    assert "File:Candidate 2.jpg" not in out
    assert re.findall(r"^\s+(\d+)  File:", out, re.M) == ["1", "2", "3", "4"] * 2
    assert out.count("1 skipped") == 2
    assert err.count("File:Candidate 2.jpg") == 2
    assert "HTTP 404" in err


def test_offline_candidates_still_fail_when_a_thumbnail_is_not_cached(example_copy, network):
    assert fetch_photos.main([str(example_copy), "--candidates"]) == 0
    config = trip.load_config(example_copy)
    trip.Http(config.user_agent, config.paths.cache).cache_file(
        network.session.urls("Candidate_2.jpg")[0]).unlink()

    assert fetch_photos.main([str(example_copy), "--candidates", "--offline"]) == 3
