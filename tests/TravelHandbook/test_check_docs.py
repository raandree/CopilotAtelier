"""Two-language document checks: anchors, links, reference labels, assets, and twin structure."""
from __future__ import annotations

from pathlib import Path

import pytest

import check_docs

# Links to a drive, a root, or another host. On Windows a UNC path, also spelled /\host or
# \/host, makes an existence check contact the host over SMB or WebDAV with the user's
# NTLM credentials; percent-encoding hides any of them from a plain prefix test.
FOREIGN_LINKS = [
    "\\\\evil-host\\share\\a.md",
    "/\\evil-host/share/b.md",
    "\\/evil-host/share/c.md",
    "%5C%5Cevil-host%5Cshare%5Cd.md",
    "%2F%2Fevil-host%2Fshare%2Fe.md",
    "%5Cevil-host%5Cf.md",
    "/evil-host/g.md",
    "C:/evil-host/h.md",
    "c:%5Cevil-host%5Ci.md",
    "C%3A%5Cevil-host%5Cj.md",
]

GUIDE_EN = """\
# \U0001F5FA\ufe0f Route

See [the weather](weather.md#temperatures), [Plan B][plan-b], and [the top](#\ufe0f-route).

| Night | Place |
|---|---|
| 1 | Alpha Village |

- Bring a map
- Bring water

> Note: the pass may be closed.

![Route map](images/route-map.png)

[Download the track](maps/route.gpx)

## \U0001F500 When plans change

Read [this section](#-when-plans-change) first.

[plan-b]: plan-b.md
"""

GUIDE_DE = """\
# \U0001F5FA\ufe0f Route

Siehe [das Wetter](weather.de.md#temperaturen), [Plan B][plan-b] und [oben](#\ufe0f-route).

| Nacht | Ort |
|---|---|
| 1 | Alphadorf |

- Karte mitnehmen
- Wasser mitnehmen

> Hinweis: Der Pass kann gesperrt sein.

![Routenkarte](images/route-map.de.png)

[Track herunterladen](maps/route.gpx)

## \U0001F500 Wenn sich Pläne ändern

Lies [diesen Abschnitt](#-wenn-sich-pläne-ändern) zuerst.

[plan-b]: plan-b.de.md
"""


def write(root, name, text):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


@pytest.fixture
def handbook(tmp_path):
    """A small matching English and German handbook with its assets."""
    root = tmp_path / "docs"
    write(root, "guide.md", GUIDE_EN)
    write(root, "guide.de.md", GUIDE_DE)
    write(root, "weather.md", "# Weather\n\n## Temperatures\n\nCold nights.\n")
    write(root, "weather.de.md", "# Wetter\n\n## Temperaturen\n\nKalte Nächte.\n")
    write(root, "plan-b.md", "# Plan B\n\nOther valleys.\n")
    write(root, "plan-b.de.md", "# Plan B\n\nAndere Täler.\n")
    for name in ("images/route-map.png", "images/route-map.de.png", "maps/route.gpx"):
        write(root, name, "synthetic")
    return root


def run(root, languages=("en", "de")):
    return check_docs.check([root], list(languages))


@pytest.mark.parametrize("heading, anchor", [
    ("\U0001F5FA\ufe0f Route", "\ufe0f-route"),
    ("\U0001F500 When plans change", "-when-plans-change"),
    ("Маршрут и карта", "маршрут-и-карта"),
    ("Day 3: Bravo Pass (2,870 m)!", "day-3-bravo-pass-2870-m"),
    ("Use `trip.py` and **bold** text", "use-trippy-and-bold-text"),
    ("snake_case stays, _emphasis_ goes", "snake_case-stays-emphasis-goes"),
    ("Wenn sich Pläne ändern", "wenn-sich-pläne-ändern"),
])
def test_github_anchor_rule(heading, anchor):
    assert check_docs.slug(heading) == anchor


def test_duplicate_headings_are_numbered(tmp_path):
    path = write(tmp_path, "notes.md", "# Notes\n\n## Notes\n\n## Notes\n\n```\n# Not a heading\n```\n")

    assert check_docs.anchors(path) == {"notes", "notes-1", "notes-2"}


def test_matching_twins_pass(handbook, capsys):
    assert run(handbook) == []
    assert check_docs.main(["--languages", "en,de", str(handbook)]) == 0
    assert "0 problems" in capsys.readouterr().out


def test_structural_differences_are_reported(handbook, capsys):
    text = GUIDE_DE.replace("- Wasser mitnehmen\n", "- Wasser mitnehmen\n- Mütze mitnehmen\n")
    text = text.replace("## \U0001F500 Wenn", "### \U0001F500 Wenn")
    text = text.replace("| 1 | Alphadorf |\n", "| 1 | Alphadorf |\n| 2 | Bravohütte |\n")
    text = text.replace("> Hinweis: Der Pass kann gesperrt sein.\n\n", "")
    write(handbook, "guide.de.md", text)
    problems = run(handbook)

    for key in ("heading levels", "table rows", "list items", "callouts"):
        assert any(f"guide.md / guide.de.md: {key} differ" in problem for problem in problems), key
    assert check_docs.main(["--languages", "en,de", str(handbook)]) == 1
    assert "guide.de.md" in capsys.readouterr().out


def test_different_images_link_targets_and_definitions_are_reported(handbook):
    text = GUIDE_DE.replace("images/route-map.de.png", "images/other.png")
    text = text.replace("(maps/route.gpx)", "(plan-b.de.md)")
    text = text.replace("[plan-b]: plan-b.de.md", "[plan-b]: plan-b.de.md\n[extra]: weather.de.md")
    text = text.replace("[Plan B][plan-b]", "[Plan B][plan-b] [Extra][extra]")
    write(handbook, "guide.de.md", text)
    write(handbook, "images/other.png", "synthetic")
    problems = run(handbook)

    for key in ("images", "link targets", "link definitions"):
        assert any(f"guide.md / guide.de.md: {key} differ" in problem for problem in problems), key


def test_missing_twin_is_reported(handbook):
    (handbook / "plan-b.de.md").unlink()
    problems = run(handbook)

    assert any(problem.endswith("plan-b.md: twin plan-b.de.md is missing") for problem in problems)


def test_undefined_and_unused_reference_labels(handbook):
    write(handbook, "guide.de.md", GUIDE_DE.replace("[plan-b]: plan-b.de.md\n", ""))
    write(handbook, "guide.md", GUIDE_EN + "[unused]: weather.md\n")
    problems = run(handbook)

    assert any(problem.endswith("guide.de.md: undefined reference [plan-b]") for problem in problems)
    assert any(problem.endswith("guide.md: unused definition [unused]") for problem in problems)


def test_task_boxes_alerts_and_footnotes_are_not_labels(handbook):
    extra = "\n- [ ] pack\n- [x] book\n\n> [!NOTE]\n> Careful.\n\nSee note[^1].\n\n[^1]: Synthetic.\n"
    write(handbook, "guide.md", GUIDE_EN + extra)
    write(handbook, "guide.de.md", GUIDE_DE + extra)

    assert run(handbook) == []


def test_missing_files_anchors_images_and_tracks(handbook):
    write(handbook, "guide.md", GUIDE_EN.replace("weather.md#temperatures", "weather.md#nowhere"))
    (handbook / "images" / "route-map.de.png").unlink()
    (handbook / "maps" / "route.gpx").unlink()
    problems = run(handbook)

    assert any(problem.endswith("guide.md: missing heading #nowhere in weather.md")
               for problem in problems)
    assert any(problem.endswith("guide.de.md: missing file images/route-map.de.png")
               for problem in problems)
    assert sum(problem.endswith("missing file maps/route.gpx") for problem in problems) == 2


def test_cyrillic_anchors_resolve(tmp_path):
    root = tmp_path / "docs"
    write(root, "route.md", "# Route\n\n## Map\n\n[Map](#map)\n")
    write(root, "route.ru.md", "# Маршрут\n\n## Карта\n\n[Карта](#карта)\n")

    assert run(root, ("en", "ru")) == []


@pytest.mark.parametrize("link", FOREIGN_LINKS)
def test_absolute_and_network_links_fail_without_touching_the_file_system(tmp_path, monkeypatch,
                                                                           link):
    root = tmp_path / "docs"
    write(root, "guide.md", f"# Guide\n\n[Elsewhere]({link}) and ![Picture]({link}#top)\n\n"
                            f"See [the share][share].\n\n[share]: {link}\n")
    checked = []
    real_exists = Path.exists

    def exists(self, *args, **kwargs):
        checked.append(str(self))
        # Anything outside the test folder is answered here, so even an unfixed check
        # sends no request to another host.
        inside = str(self).startswith(str(tmp_path))
        return real_exists(self, *args, **kwargs) if inside else False

    monkeypatch.setattr(Path, "exists", exists)

    problems = run(root, ("en",))

    assert len(problems) == 2, problems
    assert all("absolute or network path" in problem for problem in problems)
    assert any(problem.endswith(f"{link}#top; link relative to the document")
               for problem in problems)
    assert not [path for path in checked if "evil-host" in path]


def test_scheme_links_stay_unchecked_external_links(handbook):
    text = GUIDE_EN + "\n[Web](https://example.org/a.md) [Protocol-relative](//example.org/b.md)\n"
    write(handbook, "guide.md", text)
    write(handbook, "guide.de.md", GUIDE_DE + "\n[Web](https://example.org/a.md) "
                                              "[Protocol-relative](//example.org/b.md)\n")

    assert run(handbook) == []


@pytest.mark.parametrize("codes", ["english,de", "en,deutsch", "en,de-"])
def test_language_codes_must_match_entirely(handbook, codes):
    assert check_docs.main(["--languages", codes, str(handbook)]) == 2


def test_languages_come_from_the_configuration(handbook, write_config):
    config = write_config(f"""\
languages: [en, de]
user_agent: "travel-handbook-tests/1.0 (tests@example.org)"
timezone: Europe/Zurich
paths:
  docs: ["{handbook.as_posix()}"]
places:
  alpha:
    name: {{en: Alpha Village, de: Alphadorf}}
    lat: 45.9
    lon: 7.1
    source: Synthetic test data
nights:
  - {{date: 2027-07-01, place: alpha}}
labels:
  de: {{}}
""")
    (handbook / "plan-b.de.md").unlink()

    assert check_docs.main(["--config", str(config)]) == 2

    import trip
    from synthetic import labels_json

    text = config.read_text(encoding="utf-8").replace(
        "  de: {}", f"  de: {labels_json(trip.DEFAULT_LABELS['en'])}")
    config.write_text(text, encoding="utf-8")

    assert check_docs.main(["--config", str(config)]) == 1


def test_arguments_are_required():
    with pytest.raises(SystemExit) as caught:
        check_docs.main([])

    assert caught.value.code == 2
