"""Shared toolkit for the travel-handbook scripts: configuration, numbers, HTTP, drawing.

A script in this folder imports it with `import trip`. The trip configuration
is one YAML file, read as YAML 1.2 with ruamel.yaml's pure safe loader (so an
unquoted NO, yes, on, or off stays a string), validated strictly, and turned
into a Trip object. The schema is documented in references/trip-config.md.

Heavy packages (requests, matplotlib, Pillow) are imported inside the functions
that need them, so a script that only checks documents does not load them.
"""
from __future__ import annotations

import hashlib
import io
import json
import math
import os
import re
import string
import sys
import time
import warnings
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlencode, urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from ruamel.yaml import YAML
from ruamel.yaml.error import YAMLError

EXIT_OK = 0  # success
EXIT_CHECK = 1  # a check failed or a number differs; details on stdout
EXIT_CONFIG = 2  # bad arguments, invalid configuration, or an unusable path
EXIT_NETWORK = 3  # a download still failed after the bounded retries

EXIT_CODES_HELP = """exit codes:
  0  success
  1  a check failed: a chapter or document difference, or a refused photo license
  2  bad arguments, invalid configuration, or an unusable path
  3  network failure after bounded retries (rerun later; the cache keeps progress)"""

ATTRIBUTION = ("Map data © OpenStreetMap contributors, SRTM · "
               "Map style © OpenTopoMap (CC-BY-SA)")
MINUS = "\u2212"  # typographic minus sign: as wide as a plus, never broken from its digits
NBSP = "\u00a0"  # no-break space, the Russian digit-group separator


class TripError(Exception):
    """A failure the scripts report with a message and a documented exit code."""

    exit_code = EXIT_CHECK


class ConfigError(TripError):
    """The configuration or an argument is invalid; carries one message per problem."""

    exit_code = EXIT_CONFIG

    def __init__(self, problems: list[str]) -> None:
        self.problems = list(problems)
        super().__init__("; ".join(self.problems))


class NetworkError(TripError):
    """A download failed after the bounded retries, or --offline found no cached copy."""

    exit_code = EXIT_NETWORK


def configure_console() -> None:
    """Write UTF-8 to stdout and stderr; the Windows code page cannot print Cyrillic."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass


def log(message: str) -> None:
    """Print a diagnostic line to stderr; results go to stdout."""
    print(message, file=sys.stderr)


def report(error: TripError) -> None:
    if isinstance(error, ConfigError):
        log(f"invalid configuration ({len(error.problems)} problem"
            f"{'' if len(error.problems) == 1 else 's'}):")
        for problem in error.problems:
            log(f"  {problem}")
    else:
        log(f"error: {error}")


# ---------------------------------------------------------------------------
# Numbers


@dataclass(frozen=True)
class NumberFormat:
    """How one language writes numbers."""

    decimal: str
    group: str
    group_min_digits: int  # group the integer part only from this many digits on
    minus: str = MINUS


BUILTIN_NUMBER_FORMATS = {
    "en": NumberFormat(".", ",", 4),  # 1,234.5: groups from four digits
    "de": NumberFormat(",", ".", 4),  # 1.234,5: groups from four digits
    "ru": NumberFormat(",", NBSP, 5),  # 1234,5 but 12 345: groups from five digits
}


def format_number(value: float, decimals: int, fmt: NumberFormat) -> str:
    """Round half up and write the number with the language's separators."""
    quantum = Decimal(1).scaleb(-decimals)
    number = Decimal(repr(float(value))).quantize(quantum, rounding=ROUND_HALF_UP)
    if number == 0:
        number = abs(number)  # never print a negative zero
    whole, _, fraction = f"{abs(number):f}".partition(".")
    if fmt.group and len(whole) >= fmt.group_min_digits:
        groups = []
        while len(whole) > 3:  # digit groups of three
            groups.insert(0, whole[-3:])
            whole = whole[:-3]
        groups.insert(0, whole)
        whole = fmt.group.join(groups)
    sign = fmt.minus if number < 0 else ""
    return sign + whole + (fmt.decimal + fraction if fraction else "")


# ---------------------------------------------------------------------------
# Chart labels. English is built in; every other language comes from the
# configuration. Each label belongs to a feature, and only the labels of the
# features a configuration uses are required.

_LABELS: list[tuple[str, str, Any]] = [
    ("months", "common", ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]),
    ("date_format", "common", "{day} {month}"),
    ("unit_m", "common", "m"),
    ("unit_c", "common", "°C"),
    ("map_title", "map", "Where we sleep, night by night"),
    ("map_track", "map", "Route (GPS track)"),
    ("map_variant", "map", "Planned variant (approximate)"),
    ("map_day_hike", "map", "Day hike"),
    ("map_transfer", "map", "Transfer by road or rail"),
    ("map_stop", "map", "Overnight stop with its night number"),
    ("map_high", "map", "Highest point of the day"),
    ("map_area", "map", "Map area"),
    ("map_panel", "map", "Night by night"),
    ("profile_title", "map", "Elevation by night: where we sleep and the highest point "
                             "of each day"),
    ("profile_axis", "map", "Elevation (m)"),
    ("profile_sleep", "map", "Sleeping elevation"),
    ("profile_note", "map", "Elevations from the trip configuration; each place names "
                            "its source."),
    ("daylight_title", "daylight", "Daylight where we sleep"),
    ("daylight_note", "daylight", "Local time ({timezone}), calculated with the astral "
                                  "library for a flat horizon; in deep valleys the sun "
                                  "rises later and sets earlier behind the mountains."),
    ("daylight_axis", "daylight", "Local time"),
    ("daylight_day", "daylight", "Daylight"),
    ("daylight_twilight", "daylight", "Civil twilight"),
    ("daylight_night", "daylight", "Night"),
    ("daylight_length", "daylight", "{hours} h {minutes} min"),
    ("temperature_title", "climate", "Temperatures where we sleep, night by night"),
    ("temperature_note", "climate", "ERA5 reanalysis via Open-Meteo for {window} of "
                                    "{first_year}–{last_year}, corrected to each night's "
                                    "elevation. Valley nights can be colder than modelled."),
    ("temperature_axis", "climate", "Temperature (°C)"),
    ("temperature_below", "climate", "Range below 0 °C"),
    ("temperature_above", "climate", "Range above 0 °C"),
    ("temperature_cold", "climate", "Cold night (1 in 10)"),
    ("table_date", "climate", "Date"),
    ("table_place", "climate", "Place"),
    ("table_elevation", "climate", "Elevation (m)"),
    ("table_night", "climate", "Night, mean (°C)"),
    ("table_day", "climate", "Day, mean (°C)"),
    ("table_cold", "climate", "Cold night, 1 in 10 (°C)"),
    ("table_lowest", "climate", "Lowest (°C)"),
    ("table_dem_note", "climate", "DEM: elevation from the Copernicus GLO-90 model via the "
                                  "Open-Meteo elevation API."),
    ("calendar_title", "calendar", "Trip calendar: plan, decision points, and validity "
                                   "windows"),
    ("calendar_plan", "calendar", "Our plan"),
    ("calendar_marker", "calendar", "Decision point"),
    ("calendar_markers_note", "calendar", "Decision points: {items}"),
    ("plan_b_title", "plan_b", "Plan B regions and their status"),
    ("plan_b_note", "plan_b", "Status as recorded in the trip configuration. Outline: "
                              "© OpenStreetMap contributors, via Nominatim."),
    ("plan_b_route", "plan_b", "Our route"),
    ("status_open", "plan_b", "Open"),
    ("status_limited", "plan_b", "Open with limits"),
    ("status_closed", "plan_b", "Closed"),
    ("credits_title", "photos", "Photo credits"),
    ("credits_note", "photos", "All photos come from Wikimedia Commons. They were cropped "
                               "and resized; each crop keeps the license of its original "
                               "(ShareAlike where it applies)."),
    ("credits_photo", "photos", "Photo"),
    ("credits_author", "photos", "Author"),
    ("credits_license", "photos", "License"),
    ("credits_file", "photos", "File page"),
]
DEFAULT_LABELS: dict[str, dict[str, Any]] = {"en": {key: text for key, _, text in _LABELS}}
LABEL_FEATURE = {key: feature for key, feature, _ in _LABELS}
LABEL_PLACEHOLDERS = {
    "date_format": {"day", "month"},
    "daylight_note": {"timezone"},
    "daylight_length": {"hours", "minutes"},
    "temperature_note": {"window", "first_year", "last_year"},
    "calendar_markers_note": {"items"},
}
MONTHS_IN_YEAR = 12  # the months label lists one abbreviation per month

# ---------------------------------------------------------------------------
# The normalized configuration


@dataclass
class Paths:
    images: Path
    gpx: Path
    photos: Path
    cache: Path
    docs: list[Path]


@dataclass
class Place:
    key: str
    names: dict[str, str]
    lat: float
    lon: float
    elevation: float | None
    source: str
    label: tuple[float, float, str] | None  # dx, dy in display pixels (+dy is up), align


@dataclass
class Night:
    date: date
    place: str


@dataclass
class Route:
    gpx: Path | None
    my_maps: str | None
    segments: list[int] | None
    credit: dict[str, str] | None
    variants: list[list[str]]
    day_hikes: list[list[str]]
    transfers: list[list[str]]


@dataclass
class MapLabel:
    text: dict[str, str]
    lat: float
    lon: float


@dataclass
class MapSettings:
    zoom: int | None
    lat: tuple[float, float] | None
    lon_center: float | None
    margin: float
    exclude: list[str]
    locator_extent: tuple[float, float, float, float] | None
    locator_labels: list[MapLabel]


@dataclass
class Span:
    start: date
    end: date
    label: dict[str, str]
    note: dict[str, str] | None
    color: str | None


@dataclass
class Marker:
    date: date
    label: dict[str, str]


@dataclass
class Calendar:
    start: date
    end: date
    phases: list[Span]
    markers: list[Marker]
    windows: list[Span]


@dataclass
class Region:
    name: dict[str, str]
    lat: float
    lon: float
    status: str
    note: dict[str, str] | None
    offset: tuple[float, float]  # label offset from the point, in typographic points


@dataclass
class PlanB:
    extent: tuple[float, float, float, float] | None
    regions: list[Region]


@dataclass
class Climate:
    window: tuple[str, str]  # month-day pair, inclusive; may wrap past 31 Dec
    years: int
    last_year: int | None
    places: list[str]
    chapter: Path | None


@dataclass
class Photo:
    name: str
    place: str | None
    file: str
    focus: tuple[float, float]  # 0 = left or top, 1 = right or bottom
    banner: bool
    caption: dict[str, str]


@dataclass
class Candidate:
    subject: str
    category: str | None
    search: str | None
    limit: int


@dataclass
class Trip:
    path: Path
    root: Path
    languages: list[str]
    user_agent: str
    timezone_name: str
    timezone: ZoneInfo
    title: dict[str, str] | None
    country: str | None
    paths: Paths
    places: dict[str, Place]
    nights: list[Night]
    high_points: list[Night]
    route: Route | None
    map: MapSettings
    calendar: Calendar | None
    plan_b: PlanB | None
    climate: Climate | None
    photos: list[Photo]
    photo_candidates: list[Candidate]
    labels: dict[str, dict[str, Any]]
    numbers: dict[str, NumberFormat]

    @property
    def primary(self) -> str:
        return self.languages[0]

    def name(self, key: str, lang: str) -> str:
        return self.places[key].names[lang]

    def text(self, lang: str, key: str, **fields: Any) -> str:
        value = self.labels[lang][key]
        return value.format(**fields) if key in LABEL_PLACEHOLDERS else value

    def number(self, lang: str, value: float, decimals: int = 0) -> str:
        return format_number(value, decimals, self.numbers[lang])

    def elevation_text(self, lang: str, metres: float) -> str:
        return f"{self.number(lang, metres)} {self.text(lang, 'unit_m')}"

    def date_text(self, lang: str, day: date) -> str:
        months = self.labels[lang]["months"]
        return self.text(lang, "date_format", day=day.day, month=months[day.month - 1])

    def output(self, folder: Path, stem: str, lang: str, suffix: str) -> Path:
        """Name outputs like twin documents: name.png and name.<lang>.png."""
        return folder / (f"{stem}{suffix}" if lang == self.primary else f"{stem}.{lang}{suffix}")

    def night_numbers(self) -> dict[str, list[int]]:
        """Map each place to the numbers (from 1) of the nights spent there."""
        numbers: dict[str, list[int]] = {}
        for index, night in enumerate(self.nights, start=1):
            numbers.setdefault(night.place, []).append(index)
        return numbers

# ---------------------------------------------------------------------------
# Validation helpers

CONTACT_PATTERN = re.compile(r"[\w.+-]+@[\w-]+(\.[\w-]+)+|https?://\S+")
# Whole values match these through fullmatch: "^...$" with match also accepts a final line break.
KEY_PATTERN = re.compile(r"[A-Za-z0-9_-]+")
LANGUAGE_PATTERN = re.compile(r"[a-z]{2,3}(-[A-Za-z0-9]{2,8})*")
COLOUR_PATTERN = re.compile(r"#[0-9A-Fa-f]{6}")
MONTH_DAY_PATTERN = re.compile(r"(\d{2})-(\d{2})")
LEAP_YEAR = 2000  # any leap year: lets a month-day window name 29 February
MAX_ZOOM = 17  # OpenTopoMap serves tiles up to zoom 17
MAX_MERCATOR_LAT = 85  # Web Mercator tiles stop at about 85.05 degrees north and south
LOWEST_ELEVATION = -500  # metres: below the lowest dry land, so typos stand out
HIGHEST_ELEVATION = 9000  # metres: above the highest summit, so typos stand out
DEFAULT_MARGIN = 0.12  # share of the map kept free around the outermost points
MAX_MARGIN = 0.45  # a larger margin would leave no room for the route itself
FIRST_ERA5_YEAR = 1940  # the ERA5 reanalysis starts in 1940
LAST_PLAUSIBLE_YEAR = 2100  # catches a mistyped year without a yearly code change
MAX_CLIMATE_YEARS = 40  # forty yearly windows per place is already a long first download
DEFAULT_CANDIDATES = 24  # contact-sheet thumbnails per subject: six rows of four
MAX_CANDIDATES = 50  # one Commons batch: gcmlimit=50 is what stays under the rate limit
LABEL_OFFSET = (16.0, 10.0)  # display pixels right of and above a marker: clears a 19-point circle
REGION_OFFSET = (14.0, 14.0)  # points right of and above a Plan B point: clear of the dot
STATUSES = ("open", "limited", "closed")
ALIGNMENTS = ("left", "center", "right")
DEFAULT_PATHS = {"images": "docs/images", "gpx": "docs/maps/route.gpx",
                 "photos": "docs/images/photos", "cache": ".cache/travel-handbook"}
DEFAULT_DOCS = ["README.md", "docs"]
MAX_LISTED = 10  # place keys named in an "unknown place" message before it is cut short


def _show(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    if isinstance(value, dict):
        return "a mapping"
    if isinstance(value, list):
        return "a list"
    if isinstance(value, datetime):
        return f"a date and time ({value.isoformat()})"
    return repr(value)


def _join(path: str, key: Any) -> str:
    return f"{path}.{key}" if path else str(key)


class _Checker:
    """Collect one message per problem, each naming the path of the offending value."""

    def __init__(self) -> None:
        self.problems: list[str] = []
        self.languages: list[str] = []

    def add(self, path: str, message: str) -> None:
        self.problems.append(f"{path}: {message}")

    def mapping(self, value: Any, path: str, required=(), optional=()) -> dict | None:
        if not isinstance(value, dict):
            self.add(path, f"expected a mapping, got {_show(value)}")
            return None
        allowed = (*required, *optional)
        for key in value:
            if key not in allowed:
                self.add(_join(path, key), f"unknown key (allowed: {', '.join(allowed)})")
        for key in required:
            if key not in value:
                self.add(_join(path, key), "missing required key")
        return value

    def text(self, value: Any, path: str) -> str | None:
        if isinstance(value, str) and value.strip():
            return value
        self.add(path, f"expected text, got {_show(value)}")
        return None

    def number(self, value: Any, path: str, low: float | None = None,
               high: float | None = None) -> float | None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            self.add(path, f"expected a number, got {_show(value)}")
            return None
        if low is not None and value < low or high is not None and value > high:
            bound = f"between {low} and {high}" if high is not None else f"at least {low}"
            self.add(path, f"must be {bound}, got {value}")
            return None
        return value

    def integer(self, value: Any, path: str, low: int | None = None,
                high: int | None = None) -> int | None:
        if isinstance(value, bool) or not isinstance(value, int):
            self.add(path, f"expected a whole number, got {_show(value)}")
            return None
        if low is not None and value < low or high is not None and value > high:
            bound = f"between {low} and {high}" if high is not None else f"at least {low}"
            self.add(path, f"must be {bound}, got {value}")
            return None
        return value

    def flag(self, value: Any, path: str) -> bool | None:
        if isinstance(value, bool):
            return value
        self.add(path, f"expected true or false, got {_show(value)}")
        return None

    def day(self, value: Any, path: str) -> date | None:
        if isinstance(value, date) and not isinstance(value, datetime):
            return value
        if isinstance(value, str):
            try:
                return date.fromisoformat(value.strip())
            except ValueError:
                pass
        self.add(path, f"expected a date (YYYY-MM-DD), got {_show(value)}")
        return None

    def items(self, value: Any, path: str) -> list | None:
        if isinstance(value, list):
            return value
        self.add(path, f"expected a list, got {_show(value)}")
        return None

    def colour(self, value: Any, path: str) -> str | None:
        if isinstance(value, str) and COLOUR_PATTERN.fullmatch(value):
            return value
        self.add(path, f"expected a colour such as \"#2e86c1\", got {_show(value)}")
        return None

    def lang_text(self, value: Any, path: str) -> dict[str, str] | None:
        """Text in every language: one string for all, or a mapping of language to text."""
        if not self.languages:
            return None
        if isinstance(value, str) and value.strip():
            return {lang: value for lang in self.languages}
        if not isinstance(value, dict):
            self.add(path, f"expected text or a mapping of language to text, got {_show(value)}")
            return None
        for key in value:
            if key not in self.languages:
                self.add(_join(path, key),
                         f"unknown language (languages: {', '.join(self.languages)})")
        result = {}
        for lang in self.languages:
            if lang not in value:
                self.add(_join(path, lang), "missing translation")
            elif (text := self.text(value[lang], _join(path, lang))) is not None:
                result[lang] = text
        return result if len(result) == len(self.languages) else None

    def place_key(self, value: Any, path: str, place_keys: set[str]) -> str | None:
        if isinstance(value, str) and value in place_keys:
            return value
        if isinstance(value, str):
            known = sorted(place_keys)
            listed = ", ".join(known[:MAX_LISTED]) + (", ..." if len(known) > MAX_LISTED else "")
            self.add(path, f"unknown place {value!r} (places: {listed or 'none'})")
        else:
            self.add(path, f"expected a place key, got {_show(value)}")
        return None

    def extent(self, value: Any, path: str) -> tuple[float, float, float, float] | None:
        numbers = value if isinstance(value, list) and len(value) == 4 else None
        if numbers is None or any(isinstance(n, bool) or not isinstance(n, (int, float))
                                  for n in numbers):
            self.add(path, f"expected [lon_min, lat_min, lon_max, lat_max], got {_show(value)}")
            return None
        lon_min, lat_min, lon_max, lat_max = (float(n) for n in numbers)
        if lon_min >= lon_max or lat_min >= lat_max:
            self.add(path, "expected lon_min < lon_max and lat_min < lat_max")
            return None
        return lon_min, lat_min, lon_max, lat_max


def _month_day(value: Any) -> bool:
    match = MONTH_DAY_PATTERN.fullmatch(value) if isinstance(value, str) else None
    if match is None:
        return False
    try:
        date(LEAP_YEAR, int(match.group(1)), int(match.group(2)))
    except ValueError:
        return False
    return True

# ---------------------------------------------------------------------------
# Sections of the configuration

TOP_REQUIRED = ("languages", "user_agent", "timezone", "places", "nights")
TOP_OPTIONAL = ("title", "country", "paths", "high_points", "route", "map", "calendar",
                "plan_b", "climate", "photos", "photo_candidates", "labels", "numbers")


def _languages(check: _Checker, value: Any) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or not value:
        check.add("languages", f"expected a list of language codes such as [en, de], "
                               f"got {_show(value)}")
        return []
    result: list[str] = []
    for index, code in enumerate(value):
        if not isinstance(code, str) or not LANGUAGE_PATTERN.fullmatch(code):
            check.add(f"languages[{index}]",
                      f"expected a language code such as en or de, got {_show(code)}")
        elif code in result:
            check.add(f"languages[{index}]", f"duplicate language {code!r}")
        else:
            result.append(code)
    return result


def _user_agent(check: _Checker, value: Any) -> str:
    if value is None:
        return ""
    text = check.text(value, "user_agent")
    if text and not CONTACT_PATTERN.search(text):
        check.add("user_agent", "must name the tool and a contact, preferably the project's URL, "
                                "e.g. \"my-trip-handbook/1.0 (https://github.com/<owner>/"
                                "<repository>)\"; tile servers and Nominatim refuse anonymous "
                                "clients")
    if text and "@" in text:
        log("warning: user_agent contains '@', which looks like an e-mail address: every request "
            "sends it to the tile servers, Nominatim, Open-Meteo, and Wikimedia Commons. Prefer "
            "the project's URL; use a personal address only with its owner's consent.")
    return text or ""


def _timezone(check: _Checker, value: Any) -> tuple[str, ZoneInfo | None]:
    if value is None:
        return "", None
    name = check.text(value, "timezone")
    if name is None:
        return "", None
    try:
        return name, ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        check.add("timezone", f"unknown IANA time zone {name!r}")
        return name, None


def _paths(check: _Checker, value: Any, root: Path) -> Paths:
    given: dict = {}
    if value is not None:
        given = check.mapping(value, "paths", optional=(*DEFAULT_PATHS, "docs")) or {}
    resolved = {}
    for key, default in DEFAULT_PATHS.items():
        text = check.text(given[key], f"paths.{key}") if key in given else default
        resolved[key] = root / (text or default)
    docs = DEFAULT_DOCS
    if "docs" in given:
        raw = [given["docs"]] if isinstance(given["docs"], str) else given["docs"]
        items = check.items(raw, "paths.docs") or []
        docs = [text for index, item in enumerate(items)
                if (text := check.text(item, f"paths.docs[{index}]"))]
    return Paths(images=resolved["images"], gpx=resolved["gpx"], photos=resolved["photos"],
                 cache=resolved["cache"], docs=[root / item for item in docs])


def _label_position(check: _Checker, value: Any, path: str) -> tuple[float, float, str] | None:
    item = check.mapping(value, path, optional=("dx", "dy", "align"))
    if item is None:
        return None
    dx = check.number(item.get("dx", LABEL_OFFSET[0]), f"{path}.dx")
    dy = check.number(item.get("dy", LABEL_OFFSET[1]), f"{path}.dy")
    align = item.get("align", "left")
    if align not in ALIGNMENTS:
        check.add(f"{path}.align", f"expected one of {', '.join(ALIGNMENTS)}, got {_show(align)}")
        return None
    if dx is None or dy is None:
        return None
    return float(dx), float(dy), align


def _places(check: _Checker, value: Any) -> dict[str, Place]:
    if value is None:
        return {}
    if not isinstance(value, dict) or not value:
        check.add("places", f"expected a mapping of place keys to places, got {_show(value)}")
        return {}
    places = {}
    for key, raw in value.items():
        path = f"places.{key}"
        if not isinstance(key, str) or not KEY_PATTERN.fullmatch(key):
            check.add(path, "a place key may use only letters, digits, '_' and '-'")
            continue
        item = check.mapping(raw, path, ("name", "lat", "lon", "source"), ("elevation", "label"))
        if item is None:
            continue
        names = check.lang_text(item["name"], f"{path}.name") if "name" in item else None
        lat = check.number(item["lat"], f"{path}.lat", -90, 90) if "lat" in item else None
        lon = check.number(item["lon"], f"{path}.lon", -180, 180) if "lon" in item else None
        source = check.text(item["source"], f"{path}.source") if "source" in item else None
        elevation = (check.number(item["elevation"], f"{path}.elevation", LOWEST_ELEVATION,
                                  HIGHEST_ELEVATION) if "elevation" in item else None)
        label = _label_position(check, item["label"], f"{path}.label") if "label" in item else None
        if names is None or lat is None or lon is None or source is None:
            continue
        places[key] = Place(key, names, float(lat), float(lon),
                            None if elevation is None else float(elevation), source, label)
    return places


def _nights(check: _Checker, value: Any, name: str, place_keys: set[str],
            ordered: bool) -> list[Night]:
    if value is None:
        return []
    items = check.items(value, name)
    if items is None:
        return []
    if ordered and not items:
        check.add(name, "expected at least one night")
    result: list[Night] = []
    previous: tuple[int, date] | None = None
    for index, raw in enumerate(items):
        path = f"{name}[{index}]"
        item = check.mapping(raw, path, ("date", "place"))
        if item is None:
            continue
        day = check.day(item["date"], f"{path}.date") if "date" in item else None
        place = check.place_key(item["place"], f"{path}.place", place_keys) if "place" in item else None
        if day is not None and ordered and previous is not None and day <= previous[1]:
            check.add(f"{path}.date", f"must come after {name}[{previous[0]}].date "
                                      f"({previous[1].isoformat()})")
        if day is not None:
            previous = (index, day)
        if day is not None and place is not None:
            result.append(Night(day, place))
    return sorted(result, key=lambda night: night.date) if not ordered else result


def _chains(check: _Checker, value: Any, path: str, place_keys: set[str]) -> list[list[str]]:
    if value is None:
        return []
    result = []
    for index, chain in enumerate(check.items(value, path) or []):
        sub = f"{path}[{index}]"
        if not isinstance(chain, list) or len(chain) < 2:
            check.add(sub, f"expected a list of at least two place keys, got {_show(chain)}")
            continue
        keys = [check.place_key(key, f"{sub}[{j}]", place_keys) for j, key in enumerate(chain)]
        if None not in keys:
            result.append(keys)
    return result


def _route(check: _Checker, value: Any, root: Path, place_keys: set[str]) -> Route | None:
    item = check.mapping(value, "route", optional=("gpx", "my_maps", "segments", "credit",
                                                   "variants", "day_hikes", "transfers"))
    if item is None:
        return None
    if ("gpx" in item) == ("my_maps" in item):
        check.add("route", "give exactly one of gpx (a GPX file) or my_maps (a Google My Maps id)")
    gpx = None
    if "gpx" in item and (text := check.text(item["gpx"], "route.gpx")):
        gpx = root / text
    my_maps = None
    if "my_maps" in item and (text := check.text(item["my_maps"], "route.my_maps")):
        if KEY_PATTERN.fullmatch(text):
            my_maps = text
        else:
            check.add("route.my_maps", "expected the map id from the My Maps link "
                                       "(letters, digits, '_' and '-')")
    segments = None
    if "segments" in item and (items := check.items(item["segments"], "route.segments")) is not None:
        segments = []
        for index, raw in enumerate(items):
            number = check.integer(raw, f"route.segments[{index}]", 1)
            if number is not None and number in segments:
                check.add(f"route.segments[{index}]", f"duplicate segment {number}")
            elif number is not None:
                segments.append(number)
    credit = check.lang_text(item["credit"], "route.credit") if "credit" in item else None
    chains = {kind: _chains(check, item.get(kind), f"route.{kind}", place_keys)
              for kind in ("variants", "day_hikes", "transfers")}
    return Route(gpx, my_maps, segments, credit, chains["variants"], chains["day_hikes"],
                 chains["transfers"])


def _map(check: _Checker, value: Any, place_keys: set[str]) -> MapSettings:
    settings = MapSettings(None, None, None, DEFAULT_MARGIN, [], None, [])
    if value is None:
        return settings
    item = check.mapping(value, "map", optional=("zoom", "lat", "lon_center", "margin",
                                                 "exclude", "locator"))
    if item is None:
        return settings
    if "zoom" in item:
        settings.zoom = check.integer(item["zoom"], "map.zoom", 1, MAX_ZOOM)
    if "lat" in item:
        pair = item["lat"]
        if (isinstance(pair, list) and len(pair) == 2
                and all(check.number(n, "map.lat", -MAX_MERCATOR_LAT, MAX_MERCATOR_LAT)
                        is not None for n in pair)):
            if pair[0] < pair[1]:
                settings.lat = (float(pair[0]), float(pair[1]))
            else:
                check.add("map.lat", "expected [lat_min, lat_max] with lat_min < lat_max")
        elif not isinstance(pair, list) or len(pair) != 2:
            check.add("map.lat", f"expected [lat_min, lat_max], got {_show(pair)}")
    if "lon_center" in item:
        settings.lon_center = check.number(item["lon_center"], "map.lon_center", -180, 180)
    if "margin" in item:
        margin = check.number(item["margin"], "map.margin", 0, MAX_MARGIN)
        settings.margin = DEFAULT_MARGIN if margin is None else float(margin)
    if "exclude" in item:
        settings.exclude = [key for index, raw in enumerate(check.items(item["exclude"],
                                                                        "map.exclude") or [])
                            if (key := check.place_key(raw, f"map.exclude[{index}]", place_keys))]
    if "locator" in item:
        locator = check.mapping(item["locator"], "map.locator", optional=("extent", "labels"))
        if locator and "extent" in locator:
            settings.locator_extent = check.extent(locator["extent"], "map.locator.extent")
        for index, raw in enumerate(check.items(locator["labels"], "map.locator.labels") or []
                                    if locator and "labels" in locator else []):
            path = f"map.locator.labels[{index}]"
            label = check.mapping(raw, path, ("text", "lat", "lon"))
            if label is None:
                continue
            text = check.lang_text(label["text"], f"{path}.text") if "text" in label else None
            lat = check.number(label["lat"], f"{path}.lat", -90, 90) if "lat" in label else None
            lon = check.number(label["lon"], f"{path}.lon", -180, 180) if "lon" in label else None
            if text is not None and lat is not None and lon is not None:
                settings.locator_labels.append(MapLabel(text, float(lat), float(lon)))
    return settings

def _spans(check: _Checker, value: Any, path: str, with_note: bool) -> list[Span]:
    if value is None:
        return []
    spans = []
    optional = ("color", "note") if with_note else ("color",)
    for index, raw in enumerate(check.items(value, path) or []):
        sub = f"{path}[{index}]"
        item = check.mapping(raw, sub, ("start", "end", "label"), optional)
        if item is None:
            continue
        start = check.day(item["start"], f"{sub}.start") if "start" in item else None
        end = check.day(item["end"], f"{sub}.end") if "end" in item else None
        label = check.lang_text(item["label"], f"{sub}.label") if "label" in item else None
        note = check.lang_text(item["note"], f"{sub}.note") if "note" in item else None
        color = check.colour(item["color"], f"{sub}.color") if "color" in item else None
        if start is not None and end is not None and end < start:
            check.add(f"{sub}.end", f"must not come before its start ({start.isoformat()})")
            continue
        if start is not None and end is not None and label is not None:
            spans.append(Span(start, end, label, note, color))
    return spans


def _calendar(check: _Checker, value: Any, nights: list[Night]) -> Calendar | None:
    item = check.mapping(value, "calendar", optional=("start", "end", "phases", "markers",
                                                      "windows"))
    if item is None:
        return None
    phases = _spans(check, item.get("phases"), "calendar.phases", with_note=False)
    windows = _spans(check, item.get("windows"), "calendar.windows", with_note=True)
    markers = []
    for index, raw in enumerate(check.items(item["markers"], "calendar.markers") or []
                                if "markers" in item else []):
        path = f"calendar.markers[{index}]"
        marker = check.mapping(raw, path, ("date", "label"))
        if marker is None:
            continue
        day = check.day(marker["date"], f"{path}.date") if "date" in marker else None
        label = check.lang_text(marker["label"], f"{path}.label") if "label" in marker else None
        if day is not None and label is not None:
            markers.append(Marker(day, label))
    start = check.day(item["start"], "calendar.start") if "start" in item else None
    end = check.day(item["end"], "calendar.end") if "end" in item else None
    known = ([night.date for night in nights] + [span.start for span in phases]
             + [span.end for span in phases] + [marker.date for marker in markers])
    if not known and (start is None or end is None):
        check.add("calendar", "give start and end, or nights, phases, or markers to derive them")
        return None
    start = start or min(known) - timedelta(days=1)
    end = end or max(known) + timedelta(days=1)
    if end < start:
        check.add("calendar.end", f"must not come before calendar.start ({start.isoformat()})")
        return None
    return Calendar(start, end, phases, markers, windows)


def _plan_b(check: _Checker, value: Any) -> PlanB | None:
    item = check.mapping(value, "plan_b", ("regions",), ("extent",))
    if item is None:
        return None
    extent = check.extent(item["extent"], "plan_b.extent") if "extent" in item else None
    regions = []
    for index, raw in enumerate(check.items(item["regions"], "plan_b.regions") or []
                                if "regions" in item else []):
        path = f"plan_b.regions[{index}]"
        region = check.mapping(raw, path, ("name", "lat", "lon", "status"), ("note", "dx", "dy"))
        if region is None:
            continue
        name = check.lang_text(region["name"], f"{path}.name") if "name" in region else None
        lat = check.number(region["lat"], f"{path}.lat", -90, 90) if "lat" in region else None
        lon = check.number(region["lon"], f"{path}.lon", -180, 180) if "lon" in region else None
        note = check.lang_text(region["note"], f"{path}.note") if "note" in region else None
        dx = check.number(region.get("dx", REGION_OFFSET[0]), f"{path}.dx")
        dy = check.number(region.get("dy", REGION_OFFSET[1]), f"{path}.dy")
        status = region.get("status")
        if "status" in region and status not in STATUSES:
            check.add(f"{path}.status", f"expected one of {', '.join(STATUSES)}, got {_show(status)}")
            continue
        if None in (name, lat, lon, status, dx, dy):
            continue
        regions.append(Region(name, float(lat), float(lon), status, note, (float(dx), float(dy))))
    return PlanB(extent, regions)


def _climate(check: _Checker, value: Any, root: Path, place_keys: set[str],
             nights: list[Night]) -> Climate | None:
    item = check.mapping(value, "climate", ("window", "years"), ("last_year", "places", "chapter"))
    if item is None:
        return None
    window = None
    if "window" in item:
        raw = item["window"]
        if isinstance(raw, list) and len(raw) == 2 and all(_month_day(part) for part in raw):
            window = (raw[0], raw[1])
        else:
            check.add("climate.window", "expected two month-day values such as "
                                        f"[\"07-01\", \"07-14\"], got {_show(raw)}")
    years = (check.integer(item["years"], "climate.years", 1, MAX_CLIMATE_YEARS)
             if "years" in item else None)
    last_year = (check.integer(item["last_year"], "climate.last_year", FIRST_ERA5_YEAR,
                               LAST_PLAUSIBLE_YEAR) if "last_year" in item else None)
    places = list(dict.fromkeys(night.place for night in nights))
    if "places" in item:
        places = [key for index, raw in enumerate(check.items(item["places"], "climate.places")
                                                  or [])
                  if (key := check.place_key(raw, f"climate.places[{index}]", place_keys))]
        if isinstance(item["places"], list) and not item["places"]:
            check.add("climate.places", "expected at least one place")
        elif places and not set(places) & {night.place for night in nights}:
            check.add("climate.places", "no night is spent at any of these places")
    chapter = None
    if "chapter" in item and (text := check.text(item["chapter"], "climate.chapter")):
        chapter = root / text
    if window is None or years is None:
        return None
    return Climate(window, years, last_year, places, chapter)


def _focus(check: _Checker, value: Any, path: str) -> tuple[float, float] | None:
    if isinstance(value, list) and len(value) == 2:
        x = check.number(value[0], f"{path}[0]", 0, 1)
        y = check.number(value[1], f"{path}[1]", 0, 1)
        return None if x is None or y is None else (float(x), float(y))
    y = check.number(value, path, 0, 1)
    return None if y is None else (0.5, float(y))


def _photos(check: _Checker, value: Any, place_keys: set[str]) -> list[Photo]:
    if value is None:
        return []
    photos: list[Photo] = []
    names: set[str] = set()
    for index, raw in enumerate(check.items(value, "photos") or []):
        path = f"photos[{index}]"
        item = check.mapping(raw, path, ("file", "caption"), ("name", "place", "focus", "banner"))
        if item is None:
            continue
        place = check.place_key(item["place"], f"{path}.place", place_keys) if "place" in item else None
        name = item.get("name", item.get("place"))
        if name is None:
            check.add(path, "give a name (the output file stem) or a place")
            continue
        if not isinstance(name, str) or not KEY_PATTERN.fullmatch(name):
            check.add(f"{path}.name", f"expected a file stem of letters, digits, '_' and '-', "
                                      f"got {_show(name)}")
            continue
        if name in names:
            check.add(f"{path}.name", f"duplicate photo name {name!r}")
            continue
        names.add(name)
        file = check.text(item["file"], f"{path}.file") if "file" in item else None
        if file is not None and not file.startswith("File:"):
            check.add(f"{path}.file", f"expected a Commons file title such as "
                                      f"\"File:Example.jpg\", got {file!r}")
            file = None
        focus = _focus(check, item.get("focus", 0.5), f"{path}.focus")
        banner = check.flag(item["banner"], f"{path}.banner") if "banner" in item else False
        caption = check.lang_text(item["caption"], f"{path}.caption") if "caption" in item else None
        if file is not None and focus is not None and banner is not None and caption is not None:
            photos.append(Photo(name, place, file, focus, banner, caption))
    return photos


def _candidates(check: _Checker, value: Any) -> list[Candidate]:
    if value is None:
        return []
    result: list[Candidate] = []
    for index, raw in enumerate(check.items(value, "photo_candidates") or []):
        path = f"photo_candidates[{index}]"
        item = check.mapping(raw, path, ("subject",), ("category", "search", "limit"))
        if item is None:
            continue
        subject = item.get("subject")
        if not isinstance(subject, str) or not KEY_PATTERN.fullmatch(subject):
            if "subject" in item:
                check.add(f"{path}.subject", f"expected a name of letters, digits, '_' and '-', "
                                             f"got {_show(subject)}")
            continue
        if any(candidate.subject == subject for candidate in result):
            check.add(f"{path}.subject", f"duplicate subject {subject!r}")
            continue
        if ("category" in item) == ("search" in item):
            check.add(path, "give exactly one of category or search")
            continue
        category = check.text(item["category"], f"{path}.category") if "category" in item else None
        if category is not None and not category.startswith("Category:"):
            check.add(f"{path}.category", f"expected a title such as \"Category:Lakes\", "
                                          f"got {category!r}")
            continue
        search = check.text(item["search"], f"{path}.search") if "search" in item else None
        limit = check.integer(item.get("limit", DEFAULT_CANDIDATES), f"{path}.limit", 1,
                              MAX_CANDIDATES)
        if limit is not None and (category or search):
            result.append(Candidate(subject, category, search, limit))
    return result


def _placeholders_ok(check: _Checker, key: str, text: str, path: str) -> bool:
    allowed = LABEL_PLACEHOLDERS.get(key)
    if allowed is None:
        return True  # labels without placeholders are printed exactly as written
    try:
        fields = {name for _, name, _, _ in string.Formatter().parse(text) if name is not None}
    except ValueError as error:
        check.add(path, f"invalid placeholder syntax ({error})")
        return False
    unknown = sorted(fields - allowed)
    if unknown:
        names = ", ".join("{" + name + "}" for name in sorted(allowed))
        check.add(path, f"unknown placeholder {{{unknown[0]}}} (allowed: {names})")
        return False
    return True


def _labels(check: _Checker, value: Any, languages: list[str],
            features: set[str]) -> dict[str, dict[str, Any]]:
    given_all: dict = {}
    if value is not None:
        if isinstance(value, dict):
            given_all = value
            for lang in value:
                if lang not in languages:
                    check.add(f"labels.{lang}",
                              f"unknown language (languages: {', '.join(languages)})")
        else:
            check.add("labels", f"expected a mapping of language to labels, got {_show(value)}")
    result = {}
    for lang in languages:
        merged = dict(DEFAULT_LABELS.get(lang, {}))
        given = given_all.get(lang) or {}
        if not isinstance(given, dict):
            check.add(f"labels.{lang}", f"expected a mapping of label keys to text, "
                                        f"got {_show(given)}")
            given = {}
        for key, text in given.items():
            path = f"labels.{lang}.{key}"
            if key not in LABEL_FEATURE:
                check.add(path, "unknown label")
            elif key == "months":
                if (isinstance(text, list) and len(text) == MONTHS_IN_YEAR
                        and all(isinstance(month, str) and month.strip() for month in text)):
                    merged[key] = text
                else:
                    check.add(path, f"expected a list of 12 month names, got {_show(text)}")
            elif check.text(text, path) is not None and _placeholders_ok(check, key, text, path):
                merged[key] = text
        for key, feature in LABEL_FEATURE.items():
            if feature in features and key not in merged and key not in given:
                note = "" if lang in DEFAULT_LABELS else " (only English labels are built in)"
                check.add(f"labels.{lang}.{key}", f"missing label{note}")
        result[lang] = merged
    return result


def _numbers(check: _Checker, value: Any, languages: list[str]) -> dict[str, NumberFormat]:
    given_all: dict = {}
    if value is not None:
        if isinstance(value, dict):
            given_all = value
            for lang in value:
                if lang not in languages:
                    check.add(f"numbers.{lang}",
                              f"unknown language (languages: {', '.join(languages)})")
        else:
            check.add("numbers", f"expected a mapping of language to number format, "
                                 f"got {_show(value)}")
    result = {}
    for lang in languages:
        base = BUILTIN_NUMBER_FORMATS.get(lang)
        path = f"numbers.{lang}"
        if lang not in given_all:
            if base is None:
                check.add(path, f"missing number format (built in: "
                                f"{', '.join(BUILTIN_NUMBER_FORMATS)}); give decimal and group")
            else:
                result[lang] = base
            continue
        required = () if base else ("decimal", "group")
        optional = tuple(key for key in ("decimal", "group", "group_min_digits", "minus")
                         if key not in required)
        item = check.mapping(given_all[lang], path, required, optional)
        if item is None:
            continue
        start = base or BUILTIN_NUMBER_FORMATS["en"]
        values = {}
        for key, default in (("decimal", start.decimal), ("group", start.group),
                             ("minus", start.minus)):
            raw = item.get(key, default)
            if isinstance(raw, str) and (raw or key == "group"):
                values[key] = raw
            else:
                check.add(f"{path}.{key}", f"expected text, got {_show(raw)}")
        digits = check.integer(item.get("group_min_digits", start.group_min_digits),
                               f"{path}.group_min_digits", 1)
        if len(values) == 3 and digits is not None:
            result[lang] = NumberFormat(values["decimal"], values["group"], digits, values["minus"])
    return result


def load_config(path: str | Path) -> Trip:
    """Read, validate, and normalize a trip configuration; raise ConfigError on any problem."""
    path = Path(path)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ConfigError([f"{path}: cannot read the configuration "
                           f"({error.strerror or error})"]) from None
    try:
        data = YAML(typ="safe", pure=True).load(text)
    except YAMLError as error:
        mark = getattr(error, "problem_mark", None)
        where = f" at line {mark.line + 1}, column {mark.column + 1}" if mark is not None else ""
        problem = getattr(error, "problem", None) or str(error).splitlines()[0]
        raise ConfigError([f"{path.name}: not valid YAML{where}: {problem}"]) from None
    return _build(path.resolve(), data)


def _build(path: Path, data: Any) -> Trip:
    if not isinstance(data, dict):
        raise ConfigError([f"{path.name}: expected a mapping of settings at the top level, "
                           f"got {_show(data)}"])
    check = _Checker()
    check.mapping(data, "", TOP_REQUIRED, TOP_OPTIONAL)
    root = path.parent
    languages = _languages(check, data.get("languages"))
    check.languages = languages
    user_agent = _user_agent(check, data.get("user_agent"))
    timezone_name, zone = _timezone(check, data.get("timezone"))
    title = check.lang_text(data["title"], "title") if "title" in data else None
    country = check.text(data["country"], "country") if "country" in data else None
    paths = _paths(check, data.get("paths"), root)
    raw_places = data.get("places")
    place_keys = {key for key in raw_places if isinstance(key, str)} if isinstance(
        raw_places, dict) else set()
    places = _places(check, raw_places)
    nights = _nights(check, data.get("nights"), "nights", place_keys, ordered=True)
    high_points = _nights(check, data.get("high_points"), "high_points", place_keys,
                          ordered=False)
    route = _route(check, data["route"], root, place_keys) if "route" in data else None
    map_settings = _map(check, data.get("map"), place_keys)
    calendar = _calendar(check, data["calendar"], nights) if "calendar" in data else None
    plan_b = _plan_b(check, data["plan_b"]) if "plan_b" in data else None
    climate = (_climate(check, data["climate"], root, place_keys, nights)
               if "climate" in data else None)
    photos = _photos(check, data.get("photos"), place_keys)
    candidates = _candidates(check, data.get("photo_candidates"))
    features = {"common", "map", "daylight"} | {
        feature for feature, section in (("climate", "climate"), ("calendar", "calendar"),
                                         ("plan_b", "plan_b"), ("photos", "photos"))
        if section in data}
    labels = _labels(check, data.get("labels"), languages, features)
    numbers = _numbers(check, data.get("numbers"), languages)
    if check.problems:
        raise ConfigError(check.problems)
    return Trip(path=path, root=root, languages=languages, user_agent=user_agent,
                timezone_name=timezone_name, timezone=zone, title=title, country=country,
                paths=paths, places=places, nights=nights, high_points=high_points,
                route=route, map=map_settings, calendar=calendar, plan_b=plan_b,
                climate=climate, photos=photos, photo_candidates=candidates, labels=labels,
                numbers=numbers)

# ---------------------------------------------------------------------------
# HTTP: one helper for every download

MAX_ATTEMPTS = 6  # a first try and five retries: rides out a few minutes of rate limiting
DEFAULT_BACKOFF = 2.0  # seconds, times the attempt number, when no Retry-After header came
MAX_WAIT = 300.0  # seconds: a longer Retry-After means "come back later", so stop and say so
REQUEST_TIMEOUT = 120  # seconds: yearly ERA5 answers and large Commons images can be slow
RETRY_STATUSES = {429, 500, 502, 503, 504}  # rate limiting and transient server failures
CACHE_NAME_LENGTH = 40  # hex digits of the URL's SHA-256 per cache file: collisions are moot
SNIPPET_BYTES = 200  # bytes of an error answer quoted in the message: enough for an API's reason
MAX_ANSWER_BYTES = 50_000_000  # bytes: far above any tile, photo, or track; caps a runaway answer
CHUNK_BYTES = 65_536  # bytes taken per step while an answer streams in
IMAGE_FORMATS = ("PNG", "JPEG", "WEBP")  # tiles are PNG, Commons renditions JPEG, PNG, or WebP


def sleep(seconds: float) -> None:
    """Wait between attempts; tests replace this with a fake clock."""
    time.sleep(seconds)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def new_session() -> Any:
    """Return a requests session; tests replace this with a fake one."""
    import requests

    return requests.Session()


def build_url(url: str, params: dict | None = None) -> str:
    return f"{url}?{urlencode(params)}" if params else url


def retry_after(value: Any) -> float | None:
    """Seconds a Retry-After header asks for (a number or an HTTP date), or None."""
    if value is None:
        return None
    text = str(value).strip()
    if text.isdigit():
        return float(text)
    try:
        when = parsedate_to_datetime(text)
    except (TypeError, ValueError, IndexError):
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return max(0.0, (when - utcnow()).total_seconds())


def _json_answer(content: bytes) -> None:
    json.loads(content)  # raises ValueError for an HTML error page served with status 200


def _snippet(content: bytes) -> str:
    """The start of an error answer, such as an API's reason, for the error message."""
    text = " ".join(content[:SNIPPET_BYTES].decode("utf-8", "replace").split())
    return f" ({text})" if text else ""


def _read(response: Any, limit: int) -> tuple[bytes, bool]:
    """Up to limit bytes of a streamed answer, and whether it is longer; reading stops there."""
    body = bytearray()
    for chunk in response.iter_content(chunk_size=min(CHUNK_BYTES, limit + 1)):
        body += chunk
        if len(body) > limit:
            return bytes(body[:limit]), True
    return bytes(body), False


def open_image(content: bytes) -> Any:
    """Open downloaded image bytes with Pillow: IMAGE_FORMATS only, a decompression bomb refused.

    Between MAX_IMAGE_PIXELS and twice that, Pillow only warns and then decodes
    the whole image; the warning is raised as an error instead.
    """
    from PIL import Image

    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        return Image.open(io.BytesIO(content), formats=IMAGE_FORMATS)


def image_answer(content: bytes) -> None:
    """Raise ValueError unless the bytes are an image that open_image accepts."""
    try:
        with open_image(content) as image:
            image.verify()
    except Exception as error:  # Pillow raises several types for a non-image answer
        raise ValueError(f"not a {', '.join(IMAGE_FORMATS)} image of a safe size: "
                         f"{error}") from None


class Http:
    """GET with the configured User-Agent, an on-disk cache keyed by URL, and bounded retries.

    A cached answer is reused on every later run, so reruns are idempotent and
    work offline. HTTP 429 and 5xx answers are retried with a backoff that
    honours Retry-After; summary() reports how many 429 answers came back.
    """

    def __init__(self, user_agent: str, cache_dir: Path, *, offline: bool = False,
                 session: Any = None) -> None:
        self.user_agent = user_agent
        self.cache_dir = Path(cache_dir) / "http"
        self.offline = offline
        self.session = session
        self.network_requests = 0
        self.cache_hits = 0
        self.rate_limited = 0

    def cache_file(self, url: str) -> Path:
        parts = urlsplit(url)
        suffix = Path(parts.path).suffix.lower()
        if not re.fullmatch(r"\.[a-z0-9]{1,5}", suffix):
            suffix = ""
        digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:CACHE_NAME_LENGTH]
        return self.cache_dir / (parts.netloc or "local") / f"{digest}{suffix}"

    def get(self, url: str, params: dict | None = None, *, backoff: float = DEFAULT_BACKOFF,
            pause: float = 0.0, attempts: int = MAX_ATTEMPTS,
            check: Callable[[bytes], None] | None = None) -> bytes:
        full = build_url(url, params)
        cached = self.cache_file(full)
        if cached.exists():
            self.cache_hits += 1
            return cached.read_bytes()
        if self.offline:
            raise NetworkError(f"{full}: not in the cache, and --offline forbids downloading")
        if self.session is None:
            self.session = new_session()
        host = urlsplit(full).netloc
        problem = "no answer"
        for attempt in range(1, attempts + 1):
            wait = backoff * attempt
            try:
                response = self.session.get(full, headers={"User-Agent": self.user_agent},
                                            timeout=REQUEST_TIMEOUT, stream=True)
                self.network_requests += 1
                try:
                    status = response.status_code
                    # An error answer is read only as far as the start its message quotes.
                    content, longer = _read(response, MAX_ANSWER_BYTES if status == 200
                                            else SNIPPET_BYTES)
                finally:
                    response.close()
            except OSError as error:  # requests' connection and read errors are OSError subclasses
                problem = f"{type(error).__name__}: {error}"
            else:
                if status == 200:
                    if longer:
                        raise NetworkError(f"{full}: the answer is longer than "
                                           f"{MAX_ANSWER_BYTES:,} bytes; refused")
                    if check is not None:
                        try:
                            check(content)
                        except ValueError as error:
                            raise NetworkError(f"{full}: unexpected answer ({error})") from None
                    self._store(cached, content)
                    if pause:
                        sleep(pause)
                    return content
                if status == 429:
                    self.rate_limited += 1
                if status not in RETRY_STATUSES:
                    raise NetworkError(f"{full}: HTTP {status}{_snippet(content)}")
                problem = f"HTTP {status}"
                asked = retry_after(response.headers.get("Retry-After"))
                if asked is not None and asked > MAX_WAIT:
                    raise NetworkError(f"{full}: HTTP {status}, and the server asks to wait "
                                       f"{asked:.0f} s; run again later")
                if asked is not None:
                    wait = asked
            if attempt < attempts:
                log(f"{host}: {problem}; retry {attempt} of {attempts - 1} in {wait:g} s")
                sleep(wait)
        raise NetworkError(f"{full}: {problem} after {attempts} attempts; run again later")

    def get_json(self, url: str, params: dict | None = None, **options: Any) -> Any:
        return json.loads(self.get(url, params, check=_json_answer, **options))

    def _store(self, path: Path, content: bytes) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        partial = path.with_name(path.name + ".part")
        partial.write_bytes(content)
        os.replace(partial, path)

    def summary(self) -> str:
        return (f"http: {self.network_requests} network requests, {self.cache_hits} cache hits, "
                f"{self.rate_limited} HTTP 429 responses")


# ---------------------------------------------------------------------------
# Geometry

TILE_SIZE = 256  # pixels per side of a web map tile in the XYZ scheme


def to_px(lon: float, lat: float, zoom: float) -> tuple[float, float]:
    """Project longitude and latitude to Web Mercator pixels at a zoom level."""
    size = TILE_SIZE * 2 ** zoom
    lat_r = math.radians(lat)
    x = (lon + 180.0) / 360.0 * size
    y = (1 - math.log(math.tan(lat_r) + 1 / math.cos(lat_r)) / math.pi) / 2 * size
    return x, y


def from_px(x: float, y: float, zoom: float) -> tuple[float, float]:
    """Invert to_px: Web Mercator pixels back to longitude and latitude."""
    size = TILE_SIZE * 2 ** zoom
    lon = x / size * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / size))))
    return lon, lat


def lon_span(lat_min: float, lat_max: float, zoom: float, aspect: float) -> float:
    """Longitude span that fills axes of this width-to-height aspect at this zoom.

    Deriving the span from the aspect keeps tiles at their native shape; a span
    chosen any other way leaves blank strips beside the map.
    """
    size = TILE_SIZE * 2 ** zoom
    height = to_px(0, lat_min, zoom)[1] - to_px(0, lat_max, zoom)[1]
    return aspect * height / size * 360.0


def mercator(lon: float, lat: float) -> tuple[float, float]:
    """Project to Mercator with both axes in degrees, for equal-aspect outline plots."""
    return lon, math.degrees(math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)))


NOMINATIM_SEARCH = "https://nominatim.openstreetmap.org/search"
NOMINATIM_PAUSE = 1.0  # seconds: Nominatim's usage policy allows one request per second
POLYGON_THRESHOLD = 0.01  # degrees of simplification: a small answer, a recognisable outline


def country_outline(http: Http, country: str) -> list[list[tuple[float, float]]]:
    """Return the outer rings of a country's outline from Nominatim (cached)."""
    params = {"country": country, "polygon_geojson": 1, "polygon_threshold": POLYGON_THRESHOLD,
              "format": "json", "limit": 1}
    results = http.get_json(NOMINATIM_SEARCH, params, pause=NOMINATIM_PAUSE)
    if not isinstance(results, list) or not results:
        raise ConfigError([f"country: Nominatim found no country named {country!r}"])
    geometry = results[0].get("geojson") or {}
    if geometry.get("type") == "Polygon":
        polygons = [geometry["coordinates"]]
    elif geometry.get("type") == "MultiPolygon":
        polygons = geometry["coordinates"]
    else:
        raise ConfigError([f"country: Nominatim returned no outline for {country!r}"])
    return [[(float(point[0]), float(point[1])) for point in polygon[0]] for polygon in polygons]


def outline_extent(rings: list[list[tuple[float, float]]],
                   margin: float) -> tuple[float, float, float, float]:
    """Bounding box of the outline, widened by a share of its size on every side."""
    lons = [lon for ring in rings for lon, _ in ring]
    lats = [lat for ring in rings for _, lat in ring]
    pad_lon = (max(lons) - min(lons)) * margin
    pad_lat = (max(lats) - min(lats)) * margin
    return min(lons) - pad_lon, min(lats) - pad_lat, max(lons) + pad_lon, max(lats) + pad_lat


# ---------------------------------------------------------------------------
# Drawing and output

DPI = 100  # pixels per inch for every PNG: a 16-inch figure becomes 1,600 px wide
PALETTE_COLOURS = 256  # palette PNG: far smaller than RGBA and enough for tiles and charts
FIGURE_WIDTH = 16.0  # inches: 1,600 px, sharp on a laptop and legible when zoomed on a phone
HALO_WIDTH = 3.0  # points of white outline that keep text legible over tiles and lines
POINTS_PER_INCH = 72  # typographic points per inch, matplotlib's unit for marker sizes
TEXT_X = 0.01  # figure fraction where chart titles and notes start, flush with the axes
TITLE_Y = 0.975  # figure fraction of a chart title's top: just under the top edge
NOTE_Y = 0.012  # figure fraction of a chart note's baseline: just above the bottom edge
CHART_AREA = (0, 0.03, 1, 0.93)  # tight_layout box: leaves the title band and the note line free


def pyplot() -> Any:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    return plt


def halo(width: float = HALO_WIDTH) -> list:
    from matplotlib import patheffects

    return [patheffects.withStroke(linewidth=width, foreground="white")]


def marker_box(ax: Any, x: float, y: float, size: float) -> Any:
    """Display-pixel box of a marker of `size` points drawn at data (x, y)."""
    from matplotlib.transforms import Bbox

    cx, cy = ax.transData.transform((x, y))
    radius = size * ax.figure.dpi / POINTS_PER_INCH / 2
    return Bbox.from_extents(cx - radius, cy - radius, cx + radius, cy + radius)


def report_overlaps(fig: Any, items: list[tuple[str, Any]], lang: str) -> list[tuple[str, str]]:
    """Print each overlapping pair of rendered extents in which at least one is a label.

    An item is an artist, a Bbox, or a callable returning a Bbox once the figure
    is drawn. Longer translations overlap more, so every language is checked.
    """
    from matplotlib.transforms import Bbox

    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    boxes = []
    for name, item in items:
        if isinstance(item, Bbox):
            boxes.append((name, item))
        elif callable(item):
            boxes.append((name, item()))
        else:
            boxes.append((name, item.get_window_extent(renderer)))
    found = []
    for index, (first, box_a) in enumerate(boxes):
        for second, box_b in boxes[index + 1:]:
            if (first.startswith("label") or second.startswith("label")) and box_a.overlaps(box_b):
                found.append((first, second))
                log(f"[{lang}] overlap: {first} / {second}")
    log(f"[{lang}] {len(found) or 'no'} label overlap{'' if len(found) == 1 else 's'}")
    return found


def sha256_file(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save_png(fig: Any, path: Path) -> str:
    """Save a figure as a 256-colour palette PNG and return its SHA-256."""
    from PIL import Image

    buffer = io.BytesIO()
    fig.savefig(buffer, format="png", dpi=DPI, metadata={"Software": None})
    pyplot().close(fig)
    buffer.seek(0)
    with Image.open(buffer) as image:
        palette = image.convert("RGB").quantize(colors=PALETTE_COLOURS)
    path.parent.mkdir(parents=True, exist_ok=True)
    palette.save(path, format="PNG", optimize=True)
    return sha256_file(path)


def write_text(path: Path, text: str) -> str:
    """Write UTF-8 text with LF line endings and return its SHA-256."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    return sha256_file(path)


def display_path(path: Path) -> str:
    """The path relative to the working directory when possible, with forward slashes."""
    path = Path(path)
    try:
        return path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def print_output(path: Path, digest: str) -> None:
    """Print one output in sha256sum format, so a rebuild can be compared line by line."""
    print(f"{digest}  {display_path(path)}")


def argument_parser(description: str, notes: str = "") -> Any:
    import argparse

    epilog = f"{notes}\n\n{EXIT_CODES_HELP}" if notes else EXIT_CODES_HELP
    return argparse.ArgumentParser(description=description, epilog=epilog,
                                   formatter_class=argparse.RawDescriptionHelpFormatter)


def run(config_path: str, offline: bool, body: Callable[[Trip, Http], int]) -> int:
    """Load the configuration, run the body, map failures to exit codes, report HTTP use."""
    http = None
    try:
        config = load_config(config_path)
        http = Http(config.user_agent, config.paths.cache, offline=offline)
        return body(config, http)
    except TripError as error:
        report(error)
        return error.exit_code
    except OSError as error:
        log(f"error: {error}")
        return EXIT_CONFIG
    finally:
        if http is not None:
            log(http.summary())
