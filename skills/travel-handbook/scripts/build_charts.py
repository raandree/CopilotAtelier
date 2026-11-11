# /// script
# requires-python = ">=3.11"
# dependencies = ["matplotlib>=3.8", "pillow>=10.3", "requests>=2.32.4", "astral>=3.2", "ruamel.yaml>=0.18", "tzdata"]
# ///
"""Build the trip charts: per-night temperatures, daylight, trip calendar, Plan B regions.

Temperatures: ERA5 daily minimum and maximum from the Open-Meteo archive for
each night's place, corrected to its elevation. The request names ERA5 alone:
the archive's default blend of models ran about 5 °C warmer at night than a
valley weather station's normals, ERA5 within about 1 °C. A place without an
elevation gets one from the Open-Meteo elevation API (Copernicus GLO-90), and
the output says so. One request per year and place covers the configured
month-day window, and every answer is cached: ten-year daily requests are
refused with HTTP 429 after a handful of places. A window with a missing day,
which ERA5 leaves for its last five days or so, stops the run and is not
cached. Next to the chart, a Markdown table per language holds the per-night
numbers. The chapter named in climate.chapter (name.md and its twins
name.<lang>.md) must contain exactly that table; every run re-checks it, and
--check does nothing else.

Daylight: sunrise, sunset, and civil twilight at each night's place in the
trip's time zone, computed with astral for a flat horizon. The calendar and
the Plan B map draw the calendar and plan_b sections of the configuration.
"""
from __future__ import annotations

import json
import math
import re
import statistics
import sys
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from functools import partial
from itertools import zip_longest
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from astral import Observer  # noqa: E402
from astral.sun import dawn, dusk, elevation, sunrise, sunset  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402

sys.dont_write_bytecode = True  # an installed Skill folder must not collect __pycache__
import trip  # noqa: E402

USAGE = """examples (from the repository root):
  uv run skills/travel-handbook/scripts/build_charts.py handbook/trip.yaml
  uv run skills/travel-handbook/scripts/build_charts.py handbook/trip.yaml --check

stdout: "<sha256>  <path>" per output, then one line per chapter difference.
stderr: progress, retries, label overlaps, and the HTTP summary with the count
of HTTP 429 answers."""

CHARTS = ("temperatures", "daylight", "calendar", "plan-b")
ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
# ERA5 alone: over three late-autumn windows at a valley station, the default blend's nights
# ran about 5 °C above the station normals and ERA5's within about 1 °C.
ARCHIVE_MODEL = "era5"
ELEVATION_URL = "https://api.open-meteo.com/v1/elevation"
DAILY = "temperature_2m_max,temperature_2m_min"
OPEN_METEO_BACKOFF = 30.0  # seconds, times the attempt: Open-Meteo's limit resets by the minute
OPEN_METEO_PAUSE = 0.3  # seconds between requests: stays under the free per-minute limit
ARCHIVE_DELAY = 7  # days: ERA5 reaches the archive about five days late; a week is safe
COLD_QUANTILE = 0.10  # the cold night is the 10th percentile: one night in ten is colder
MEAN_DECIMALS = 1  # tenths for means: their spread across nights is a few degrees
EXTREME_DECIMALS = 0  # whole degrees for single-night extremes: tenths would be false precision
DEM_MARK = "(DEM)"

TEMPERATURE_HEIGHT = 7.4  # inches: room for date and place names under the bars
DAYLIGHT_HEIGHT = 6.6  # inches: a day of hours with readable bands
CALENDAR_BASE = 2.6  # inches for the title, the day axis, and the footnote
CALENDAR_ROW = 0.75  # inches per calendar row
PLAN_B_HEIGHT = 7.0  # inches: the map beside a list of up to about eight regions
BAR_WIDTH = 0.62  # share of a night's slot taken by its temperature bar
INSIDE_LABEL_MIN = 3.0  # degrees: a shorter bar cannot hold its night value, which then goes under the whisker
WHISKER = 0.14  # half width, in nights, of the cold-night whisker's cap
TEMPERATURE_FLOOR = 3  # degrees of room under the coldest whisker
TEMPERATURE_ROOF = 4  # degrees of room over the warmest day for its label
MAX_TIME_LABELS = 12  # nights with sunrise and sunset printed; more would crowd the chart
HOURS_IN_DAY = 24  # the daylight chart's time axis spans at most one day
PHASE_HEIGHT = 0.62  # share of a calendar row taken by a phase bar
WINDOW_HEIGHT = 0.5  # share of a calendar row taken by a validity window bar
NARROW_PHASE = 1.5  # days: a narrower phase gets its label under the bar
MARKER_LIFT = 0.48  # rows above the plan row's centre for the decision diamonds
LIGHT_INK = 170  # perceived brightness above which a bar gets dark text
LIST_TOP = 0.84  # figure fraction of the first Plan B list entry
LIST_STEP = 0.09  # figure fraction between Plan B list entries
LIST_SPAN = 0.72  # figure fraction the Plan B list may fill
LIST_BADGE_X = 0.665  # figure fraction of the list's numbered badges, just right of the map
LIST_TEXT_X = 0.685  # figure fraction where list names and notes start, after the badge
LIST_NAME_LIFT = 0.012  # figure fraction a region's name sits above its badge's centre
LIST_NOTE_DROP = 0.022  # figure fraction a region's note sits below its badge's centre
PLAN_B_AXES = (0.01, 0.06, 0.63, 0.84)  # map axes: the left two thirds, under the title
CALENDAR_AREA = (0, 0.05, 1, 0.92)  # tight_layout box: the decision legend needs a taller band
PLAN_B_MARGIN = 0.08  # share of the outline's size kept around the Plan B map
FONT_TITLE = 15  # points: chart titles
FONT_TEXT = 9.5  # points: legends, values, and lists
FONT_SMALL = 8.5  # points: notes and tick labels

WARM = "#e59866"
COLD = "#5499c7"
DEEP = "#1a5276"
FROST = "#ebf5fb"
NIGHT_SKY = "#17202a"
TWILIGHT = "#5d6d7e"
DAYLIGHT = "#fcf3cf"
SUN_LINE = "#d68910"
ROUTE = "#b03a2e"
SEA = "#e8edf1"
LAND = "#fbf8f1"
BORDER = "#6e6e6e"
NOTE = "#5d6d7e"
DECISION = "#154360"
STATUS_COLOUR = {"open": "#239b56", "limited": "#d68910", "closed": "#a93226"}
PHASE_COLOURS = ["#76d7c4", "#82e0aa", "#f8c471", "#f1948a", "#bb8fce", "#85c1e9"]
WINDOW_COLOURS = ["#2874a6", "#7d3c98", "#b9770e", "#148f77"]


@dataclass
class Stats:
    night: float  # mean daily minimum
    day: float  # mean daily maximum
    cold: float  # 10th percentile of the daily minimum
    lowest: float  # lowest daily minimum


@dataclass
class ClimateData:
    stats: dict[str, Stats]
    elevations: dict[str, float]
    dem_places: list[str]
    first_year: int
    last_year: int
    window: tuple[date, date]  # the last year's window, for labels


def _on(year: int, month_day: str) -> date:
    month, day = (int(part) for part in month_day.split("-"))
    try:
        return date(year, month, day)
    except ValueError:
        return date(year, month, day - 1)  # 29 February in a common year


def window_dates(window: tuple[str, str], year: int) -> tuple[date, date]:
    """First and last day of the month-day window that starts in year."""
    start = _on(year, window[0])
    end = _on(year + 1 if window[1] < window[0] else year, window[1])
    return start, end


def default_last_year(window: tuple[str, str], today: date) -> int:
    """The latest year whose window ended at least ARCHIVE_DELAY days ago."""
    year = today.year
    while window_dates(window, year)[1] > today - timedelta(days=ARCHIVE_DELAY):
        year -= 1
    return year


def quantile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def window_stats(daily: dict) -> Stats:
    """Summarize the daily minimum and maximum of every day in the windows."""
    lows = [value for value in daily.get("temperature_2m_min", []) if value is not None]
    highs = [value for value in daily.get("temperature_2m_max", []) if value is not None]
    if not lows or not highs:
        raise trip.NetworkError("Open-Meteo returned no temperatures for the window")
    return Stats(statistics.fmean(lows), statistics.fmean(highs),
                 quantile(lows, COLD_QUANTILE), min(lows))


def dem_elevation(http: trip.Http, place: trip.Place) -> float:
    """Elevation from the Copernicus GLO-90 model via the Open-Meteo elevation API."""
    answer = http.get_json(ELEVATION_URL, {"latitude": place.lat, "longitude": place.lon},
                           backoff=OPEN_METEO_BACKOFF, pause=OPEN_METEO_PAUSE)
    values = answer.get("elevation") if isinstance(answer, dict) else None
    if not values or values[0] is None:
        raise trip.NetworkError(f"{ELEVATION_URL}: no elevation for places.{place.key}")
    return float(values[0])


def window_days(content: bytes, place: str, start: date, end: date) -> dict[str, list[float]]:
    """Every day's maximum and minimum of one yearly window from an archive answer.

    ERA5 reaches the archive about five days late, and the archive answers a day
    it lacks with null. A window with a missing day fails the run, and as the
    check of a download it keeps that answer out of the cache.
    """
    answer = json.loads(content)
    daily = answer.get("daily") if isinstance(answer, dict) else None
    series = {name: daily.get(name) if isinstance(daily, dict) else None
              for name in DAILY.split(",")}
    columns = [values if isinstance(values, list) else [] for values in series.values()]
    days = (end - start).days + 1
    complete = sum(all(isinstance(value, (int, float)) and math.isfinite(value) for value in row)
                   for row in zip(*columns))
    if complete != days or any(len(values) != days for values in columns):
        raise trip.NetworkError(f"places.{place}: the ERA5 archive has {complete} of {days} days "
                                f"for {start.isoformat()} to {end.isoformat()}; ERA5 arrives about "
                                "five days late, so for a recent window choose an earlier "
                                "climate.last_year or run again later")
    return series


def fetch_climate(config: trip.Trip, http: trip.Http) -> ClimateData:
    """ERA5 statistics per climate place: one cached request per year and place."""
    climate = config.climate
    last_year = climate.last_year or default_last_year(climate.window, date.today())
    first_year = last_year - climate.years + 1
    stats, elevations, dem_places = {}, {}, []
    for key in climate.places:
        place = config.places[key]
        height = place.elevation
        if height is None:
            height = dem_elevation(http, place)
            dem_places.append(key)
            trip.log(f"places.{key}: no elevation configured; using "
                     f"{config.number(config.primary, height)} m from the Copernicus GLO-90 "
                     f"model (Open-Meteo elevation API)")
        elevations[key] = height
        merged: dict[str, list] = {"temperature_2m_max": [], "temperature_2m_min": []}
        for year in range(first_year, last_year + 1):
            start, end = window_dates(climate.window, year)
            read_window = partial(window_days, place=key, start=start, end=end)
            content = http.get(ARCHIVE_URL, {
                "latitude": place.lat, "longitude": place.lon, "elevation": round(height),
                "start_date": start.isoformat(), "end_date": end.isoformat(),
                "daily": DAILY, "timezone": config.timezone_name, "models": ARCHIVE_MODEL,
            }, backoff=OPEN_METEO_BACKOFF, pause=OPEN_METEO_PAUSE, check=read_window)
            for name, values in read_window(content).items():
                merged[name].extend(values)
        stats[key] = window_stats(merged)
    return ClimateData(stats, elevations, dem_places, first_year, last_year,
                       window_dates(climate.window, last_year))


# ---------------------------------------------------------------------------
# The per-night table and the chapter check

TABLE_KEYS = ("table_date", "table_place", "table_elevation", "table_night", "table_day",
              "table_cold", "table_lowest")


def table_header(config: trip.Trip, lang: str) -> list[str]:
    return [config.text(lang, key) for key in TABLE_KEYS]


def table_rows(config: trip.Trip, data: ClimateData, lang: str) -> list[list[str]]:
    rows = []
    for night in config.nights:
        if night.place not in data.stats:
            continue
        stats = data.stats[night.place]
        height = config.number(lang, data.elevations[night.place])
        if night.place in data.dem_places:
            height = f"{height} {DEM_MARK}"
        rows.append([config.date_text(lang, night.date), config.name(night.place, lang), height,
                     config.number(lang, stats.night, MEAN_DECIMALS),
                     config.number(lang, stats.day, MEAN_DECIMALS),
                     config.number(lang, stats.cold, EXTREME_DECIMALS),
                     config.number(lang, stats.lowest, EXTREME_DECIMALS)])
    return rows


def markdown_table(header: list[str], rows: list[list[str]]) -> str:
    def line(cells: list[str]) -> str:
        return "| " + " | ".join(cell.replace("|", "\\|") for cell in cells) + " |"

    return "\n".join([line(header), "|" + "|".join("---" for _ in header) + "|",
                      *(line(row) for row in rows)]) + "\n"


def table_document(config: trip.Trip, data: ClimateData, lang: str) -> str:
    text = markdown_table(table_header(config, lang), table_rows(config, data, lang))
    if data.dem_places:
        text += "\n" + config.text(lang, "table_dem_note") + "\n"
    return text


def _cells(line: str) -> list[str]:
    body = line.strip()
    body = body[1:] if body.startswith("|") else body
    body = body[:-1] if body.endswith("|") and not body.endswith("\\|") else body
    return [cell.strip().replace("\\|", "|") for cell in re.split(r"(?<!\\)\|", body)]


def _tables(text: str) -> list[list[list[str]]]:
    tables, current = [], []
    for line in text.split("\n"):
        if line.lstrip().startswith("|"):
            current.append(_cells(line))
        elif current:
            tables.append(current)
            current = []
    if current:
        tables.append(current)
    return tables


def check_chapter(path: Path, header: list[str], rows: list[list[str]], source: Path) -> list[str]:
    """Compare the chapter's table with the computed rows; one message per difference."""
    name = trip.display_path(path)
    if not path.exists():
        return [f"{name}: chapter not found (climate.chapter); paste the table from "
                f"{trip.display_path(source)}"]
    table = next((table for table in _tables(path.read_text(encoding="utf-8"))
                  if table[0] == header), None)
    if table is None:
        return [f"{name}: no table with the header | {' | '.join(header)} |; paste the table "
                f"from {trip.display_path(source)}"]
    expected = {(row[0], row[1]): row for row in rows}
    found = {}
    problems = []
    for row in table[2:]:
        key = (row[0], row[1] if len(row) > 1 else "")
        found[key] = row
        if key not in expected:
            problems.append(f"{name}: row '{key[0]} | {key[1]}' is not a night of the plan")
    for key, want in expected.items():
        got = found.get(key)
        if got is None:
            problems.append(f"{name}: row '{key[0]} | {key[1]}' is missing")
            continue
        for column, (have, should) in enumerate(zip_longest(got, want, fillvalue="")):
            if have != should:
                title = header[column] if column < len(header) else f"column {column + 1}"
                problems.append(f"{name}: row '{key[0]} | {key[1]}': {title} is {have!r} in the "
                                f"chapter, computed {should!r}")
    return problems


def check_chapters(config: trip.Trip, data: ClimateData, chapter: Path | None) -> list[str]:
    problems = []
    for lang in config.languages:
        path = config.output(chapter.parent, chapter.stem, lang, chapter.suffix)
        source = config.output(config.paths.images, "weather-temperatures", lang, ".md")
        problems += check_chapter(path, table_header(config, lang),
                                  table_rows(config, data, lang), source)
    return problems

# ---------------------------------------------------------------------------
# Charts


def _frame(fig, title: str, note: str) -> None:
    fig.text(trip.TEXT_X, trip.TITLE_Y, title, fontsize=FONT_TITLE, fontweight="bold", va="top")
    fig.text(trip.TEXT_X, trip.NOTE_Y, note, fontsize=FONT_SMALL, color=NOTE)


def _tidy(ax) -> None:
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)


def _night_ticks(ax, config: trip.Trip, lang: str, nights: list[trip.Night],
                 pad: float = 0.6, suffix=None) -> None:
    ax.set_xticks(range(len(nights)))
    ax.set_xticklabels([f"{config.date_text(lang, night.date)}  {config.name(night.place, lang)}"
                        + (f"  {suffix(night)}" if suffix else "")
                        for night in nights], rotation=45, ha="right", rotation_mode="anchor",
                       fontsize=FONT_SMALL + 0.5)
    ax.set_xlim(-pad, len(nights) - 1 + pad)  # pad is room at each end, in night slots


def chart_temperatures(config: trip.Trip, data: ClimateData, lang: str):
    nights = [night for night in config.nights if night.place in data.stats]
    fig, ax = plt.subplots(figsize=(trip.FIGURE_WIDTH, TEMPERATURE_HEIGHT), dpi=trip.DPI)
    stats = [data.stats[night.place] for night in nights]
    bottom = math.floor(min(item.cold for item in stats)) - TEMPERATURE_FLOOR
    top = math.ceil(max(item.day for item in stats)) + TEMPERATURE_ROOF
    if bottom < 0:
        ax.axhspan(bottom, 0, color=FROST, zorder=0)
    ax.axhline(0, color=NOTE, lw=1, zorder=1)
    for x, (night, item) in enumerate(zip(nights, stats, strict=True)):
        if item.night < 0:
            ax.bar(x, min(item.day, 0) - item.night, bottom=item.night, width=BAR_WIDTH,
                   color=COLD, zorder=3)
        if item.day > 0:
            ax.bar(x, item.day - max(item.night, 0), bottom=max(item.night, 0), width=BAR_WIDTH,
                   color=WARM, zorder=3)
        ax.plot([x, x], [item.cold, item.night], color=DEEP, lw=1.4, zorder=2)
        ax.plot([x - WHISKER, x + WHISKER], [item.cold, item.cold], color=DEEP, lw=1.4, zorder=2)
        ax.annotate(f"{config.number(lang, item.day)}°", (x, item.day), xytext=(0, 3),
                    textcoords="offset points", ha="center", va="bottom", fontsize=FONT_TEXT,
                    fontweight="bold", color="#a04000")
        # The night value stays in its own slot: inside the bar above its lower edge, or
        # under the whisker's cap when the bar is too short to hold it.
        night_text = f"{config.number(lang, item.night)}°"
        if item.day - item.night >= INSIDE_LABEL_MIN:
            ax.annotate(night_text, (x, item.night), xytext=(0, 2), textcoords="offset points",
                        ha="center", va="bottom", fontsize=FONT_SMALL + 0.5,
                        color="white" if item.night < 0 else DEEP, zorder=4)
        else:
            ax.annotate(night_text, (x, item.cold), xytext=(0, -2), textcoords="offset points",
                        ha="center", va="top", fontsize=FONT_SMALL + 0.5, color=DEEP, zorder=4)
    _night_ticks(ax, config, lang, nights,
                 suffix=lambda night: config.elevation_text(lang, data.elevations[night.place]))
    ax.set_ylim(bottom, top)
    ax.set_ylabel(config.text(lang, "temperature_axis"))
    ax.grid(axis="y", color="#d6dbdf", lw=0.6)
    _tidy(ax)
    ax.legend(handles=[Patch(color=WARM, label=config.text(lang, "temperature_above")),
                       Patch(color=COLD, label=config.text(lang, "temperature_below")),
                       Line2D([], [], color=DEEP, lw=1.4, label=config.text(lang, "temperature_cold"))],
              loc="lower left", bbox_to_anchor=(0, 1), ncol=3, frameon=False, fontsize=FONT_TEXT)
    window = (f"{config.date_text(lang, data.window[0])}–"
              f"{config.date_text(lang, data.window[1])}")
    note = config.text(lang, "temperature_note", window=window, first_year=data.first_year,
                       last_year=data.last_year)
    if data.dem_places:
        note += " " + config.text(lang, "table_dem_note")
    _frame(fig, config.text(lang, "temperature_title"), note)
    fig.tight_layout(rect=trip.CHART_AREA)
    return fig


@dataclass
class Daylight:
    date: date
    place: str
    dawn: datetime | None
    sunrise: datetime | None
    sunset: datetime | None
    dusk: datetime | None


def daylight_rows(config: trip.Trip) -> list[Daylight]:
    """Civil dawn, sunrise, sunset, and civil dusk per night, for a flat horizon."""
    rows = []
    for night in config.nights:
        place = config.places[night.place]
        observer = Observer(latitude=place.lat, longitude=place.lon, elevation=0)
        events = {}
        for name, event in (("dawn", dawn), ("sunrise", sunrise), ("sunset", sunset),
                            ("dusk", dusk)):
            try:
                events[name] = event(observer, date=night.date, tzinfo=config.timezone)
            except ValueError:  # the sun never reaches that angle: polar day, night, or dusk
                events[name] = None
        rows.append(Daylight(night.date, night.place, **events))
    return rows


def _hours(moment: datetime) -> float:
    return moment.hour + moment.minute / 60 + moment.second / 3600


def _bands(config: trip.Trip, row: Daylight) -> tuple[float, float, float, float]:
    """Dawn, sunrise, sunset, and dusk in hours, filling gaps for polar days and nights."""
    if row.sunrise is None or row.sunset is None:
        place = config.places[row.place]
        noon = datetime(row.date.year, row.date.month, row.date.day, 12, tzinfo=config.timezone)
        if elevation(Observer(place.lat, place.lon, 0), noon) > 0:
            return 0.0, 0.0, float(HOURS_IN_DAY), float(HOURS_IN_DAY)
        rise = set_ = HOURS_IN_DAY / 2
    else:
        rise, set_ = _hours(row.sunrise), _hours(row.sunset)
    first = _hours(row.dawn) if row.dawn else (0.0 if row.sunrise else rise)
    last = _hours(row.dusk) if row.dusk else (float(HOURS_IN_DAY) if row.sunset else set_)
    return first, rise, set_, last


def chart_daylight(config: trip.Trip, lang: str):
    rows = daylight_rows(config)
    bands = [_bands(config, row) for row in rows]
    x = list(range(len(rows)))
    first, rise, set_, last = (list(series) for series in zip(*bands, strict=True))
    low = max(0, math.floor(min(first)) - 1)
    high = min(HOURS_IN_DAY, math.ceil(max(last)) + 1)
    fig, ax = plt.subplots(figsize=(trip.FIGURE_WIDTH, DAYLIGHT_HEIGHT), dpi=trip.DPI)
    floor, ceiling = [low] * len(x), [high] * len(x)
    for bottom, top, colour in ((floor, first, NIGHT_SKY), (first, rise, TWILIGHT),
                                (rise, set_, DAYLIGHT), (set_, last, TWILIGHT),
                                (last, ceiling, NIGHT_SKY)):
        # One full-width bar per night; the edge in the same colour hides seams.
        ax.bar(x, [upper - lower for lower, upper in zip(bottom, top, strict=True)], bottom=bottom,
               width=1.0, color=colour, edgecolor=colour, linewidth=0.6)
    for series in (rise, set_):
        ax.hlines(series, [index - 0.5 for index in x], [index + 0.5 for index in x],
                  color=SUN_LINE, lw=2)
    every = math.ceil(len(rows) / MAX_TIME_LABELS)
    for index in range(0, len(rows), every):
        row = rows[index]
        if row.sunrise is None or row.sunset is None:
            continue
        minutes = int((row.sunset - row.sunrise).total_seconds() // 60)
        ax.annotate(f"{row.sunrise:%H:%M}", (index, rise[index]), xytext=(0, 3),
                    textcoords="offset points", ha="center", va="bottom", fontsize=FONT_SMALL,
                    color="#7e5109")
        ax.annotate(f"{row.sunset:%H:%M}", (index, set_[index]), xytext=(0, -3),
                    textcoords="offset points", ha="center", va="top", fontsize=FONT_SMALL,
                    color="#7e5109")
        ax.text(index, (rise[index] + set_[index]) / 2,
                config.text(lang, "daylight_length", hours=minutes // 60, minutes=minutes % 60),
                ha="center", va="center", rotation=90, fontsize=FONT_SMALL, fontweight="bold",
                color="#7e5109")
    nights = [trip.Night(row.date, row.place) for row in rows]
    _night_ticks(ax, config, lang, nights, pad=0.5)
    ax.set_ylim(low, high)
    ax.set_yticks(range(low, high + 1, 2))
    ax.set_yticklabels([f"{hour:02d}:00" for hour in range(low, high + 1, 2)])
    ax.set_ylabel(config.text(lang, "daylight_axis"))
    _tidy(ax)
    ax.legend(handles=[Patch(color=DAYLIGHT, ec=SUN_LINE, label=config.text(lang, "daylight_day")),
                       Patch(color=TWILIGHT, label=config.text(lang, "daylight_twilight")),
                       Patch(color=NIGHT_SKY, label=config.text(lang, "daylight_night"))],
              loc="lower left", bbox_to_anchor=(0, 1), ncol=3, frameon=False, fontsize=FONT_TEXT)
    _frame(fig, config.text(lang, "daylight_title"),
           config.text(lang, "daylight_note", timezone=config.timezone_name))
    fig.tight_layout(rect=trip.CHART_AREA)
    return fig


def _ink(colour: str) -> str:
    """Dark or white text, whichever reads better on the colour."""
    red, green, blue = (int(colour[index:index + 2], 16) for index in (1, 3, 5))
    brightness = 0.299 * red + 0.587 * green + 0.114 * blue  # ITU-R BT.601 luma weights
    return "#1c2833" if brightness > LIGHT_INK else "white"


def chart_calendar(config: trip.Trip, lang: str):
    calendar = config.calendar
    span = (calendar.end - calendar.start).days + 1
    rows = 1 + len(calendar.windows)
    fig, ax = plt.subplots(figsize=(trip.FIGURE_WIDTH, CALENDAR_BASE + CALENDAR_ROW * rows),
                           dpi=trip.DPI)

    def day(moment: date) -> float:
        return float((moment - calendar.start).days)

    for index in range(1, span, 2):
        ax.axvspan(index, index + 1, color="#f4f6f6", zorder=0)
    plan = rows - 1
    labels = []
    for index, phase in enumerate(calendar.phases):
        colour = phase.color or PHASE_COLOURS[index % len(PHASE_COLOURS)]
        x0, x1 = max(day(phase.start), 0), min(day(phase.end) + 1, span)
        ax.barh(plan, x1 - x0, left=x0, height=PHASE_HEIGHT, color=colour, ec="white", zorder=2)
        if x1 - x0 < NARROW_PHASE:
            text = ax.text((x0 + x1) / 2, plan - PHASE_HEIGHT / 2 - 0.08, phase.label[lang],
                           ha="center", va="top", fontsize=FONT_SMALL, fontweight="bold",
                           color=colour if _ink(colour) == "white" else "#1c2833", zorder=3)
        else:
            text = ax.text((x0 + x1) / 2, plan, phase.label[lang], ha="center", va="center",
                           fontsize=FONT_TEXT, fontweight="bold", color=_ink(colour), zorder=3)
        labels.append((f"label phase {index + 1}", text))
    for number, marker in enumerate(calendar.markers, start=1):
        x = day(marker.date) + 0.5
        ax.plot(x, plan + MARKER_LIFT, marker="D", ms=13, color=DECISION, zorder=4)
        ax.text(x, plan + MARKER_LIFT, str(number), ha="center", va="center",
                fontsize=FONT_SMALL - 0.5, color="white", fontweight="bold", zorder=5)
    for index, window in enumerate(calendar.windows):
        y = plan - 1 - index
        colour = window.color or WINDOW_COLOURS[index % len(WINDOW_COLOURS)]
        x0, x1 = max(day(window.start), 0), min(day(window.end) + 1, span)
        if x1 <= x0:
            continue
        ax.barh(y, x1 - x0, left=x0, height=WINDOW_HEIGHT, color=colour, zorder=2)
        if window.note:
            note = window.note[lang]
            note = ("← " if day(window.start) < 0 else "") + note
            note += " →" if day(window.end) + 1 > span else ""
            labels.append((f"label window {index + 1}",
                           ax.text(x0 + 0.3, y, note, ha="left", va="center",
                                   fontsize=FONT_TEXT, color=_ink(colour), fontweight="bold",
                                   zorder=3)))
    ticks = [calendar.start + timedelta(days=index) for index in range(span)]
    months = config.labels[lang]["months"]
    ax.set_xticks([index + 0.5 for index in range(span)])
    ax.set_xticklabels([f"{moment.day}\n{months[moment.month - 1]}"
                        if moment == calendar.start or moment.day == 1 else str(moment.day)
                        for moment in ticks], fontsize=FONT_SMALL)
    ax.set_xlim(0, span)
    ax.set_ylim(-0.6, rows - 0.4 + MARKER_LIFT)
    ax.set_yticks(range(rows))
    ax.set_yticklabels([window.label[lang] for window in reversed(calendar.windows)]
                       + [config.text(lang, "calendar_plan")], fontsize=FONT_TEXT + 0.5)
    ax.tick_params(axis="y", length=0)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    note = ""
    if calendar.markers:
        ax.legend(handles=[Line2D([], [], ls="", marker="D", ms=9, color=DECISION,
                                  label=config.text(lang, "calendar_marker"))],
                  loc="lower right", bbox_to_anchor=(1, 1), frameon=False, fontsize=FONT_TEXT)
        items = "; ".join(f"{number} {marker.label[lang]}"
                          for number, marker in enumerate(calendar.markers, start=1))
        note = config.text(lang, "calendar_markers_note", items=items)
    _frame(fig, config.text(lang, "calendar_title"), note)
    fig.tight_layout(rect=CALENDAR_AREA)
    trip.report_overlaps(fig, labels, lang)
    return fig


def chart_plan_b(config: trip.Trip, lang: str, outline):
    plan_b = config.plan_b
    fig = plt.figure(figsize=(trip.FIGURE_WIDTH, PLAN_B_HEIGHT), dpi=trip.DPI)
    ax = fig.add_axes(PLAN_B_AXES)
    ax.set_facecolor(SEA)
    for ring in outline or []:
        ax.fill(*zip(*(trip.mercator(lon, lat) for lon, lat in ring), strict=True), fc=LAND,
                ec=BORDER, lw=1)
    stops = [config.places[night.place] for night in config.nights]
    if plan_b.extent:
        extent = plan_b.extent
    elif outline:
        extent = trip.outline_extent(outline, PLAN_B_MARGIN)
    else:
        lons = [region.lon for region in plan_b.regions] + [place.lon for place in stops]
        lats = [region.lat for region in plan_b.regions] + [place.lat for place in stops]
        extent = trip.outline_extent([list(zip(lons, lats, strict=True))], PLAN_B_MARGIN)
    route = [trip.mercator(place.lon, place.lat) for place in stops]
    ax.plot(*zip(*route, strict=True), color=ROUTE, lw=2.6, solid_joinstyle="round", zorder=3)
    labels = []
    for number, region in enumerate(plan_b.regions, start=1):
        x, y = trip.mercator(region.lon, region.lat)
        ax.plot(x, y, "o", ms=4, color="#1c1c1c", zorder=4)
        labels.append((f"label region {number}", ax.annotate(
            str(number), (x, y), xytext=region.offset, textcoords="offset points", ha="center",
            va="center", fontsize=FONT_TEXT + 0.5, fontweight="bold", color="white", zorder=5,
            bbox={"boxstyle": "circle,pad=0.3", "fc": STATUS_COLOUR[region.status], "ec": "white",
                  "lw": 1.5},
            arrowprops={"arrowstyle": "-", "color": "#34495e", "lw": 0.9})))
    x0, y0 = trip.mercator(extent[0], extent[1])
    x1, y1 = trip.mercator(extent[2], extent[3])
    ax.set_xlim(x0, x1)
    ax.set_ylim(y0, y1)
    ax.set_aspect("equal")
    ax.set_anchor("NW")
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_edgecolor("#aab7b8")
    step = min(LIST_STEP, LIST_SPAN / max(len(plan_b.regions), 1))
    for index, region in enumerate(plan_b.regions):
        y = LIST_TOP - index * step
        fig.text(LIST_BADGE_X, y, str(index + 1), fontsize=FONT_TEXT + 1, fontweight="bold",
                 color="white", ha="center", va="center",
                 bbox={"boxstyle": "circle,pad=0.3", "fc": STATUS_COLOUR[region.status],
                       "ec": "none"})
        name = fig.text(LIST_TEXT_X, y + LIST_NAME_LIFT, region.name[lang],
                        fontsize=FONT_TEXT + 1, fontweight="bold", va="center")
        labels.append((f"label list {index + 1}", name))
        if region.note:
            labels.append((f"label note {index + 1}",
                           fig.text(LIST_TEXT_X, y - LIST_NOTE_DROP, region.note[lang],
                                    fontsize=FONT_TEXT, color="#4d5656", va="center")))
    ax.legend(handles=[Patch(color=STATUS_COLOUR[status], label=config.text(lang, f"status_{status}"))
                       for status in trip.STATUSES]
              + [Line2D([], [], color=ROUTE, lw=2.2, label=config.text(lang, "plan_b_route"))],
              loc="lower left", fontsize=FONT_TEXT, framealpha=0.95)
    _frame(fig, config.text(lang, "plan_b_title"), config.text(lang, "plan_b_note"))
    trip.report_overlaps(fig, labels, lang)
    return fig


# ---------------------------------------------------------------------------
# Command line


def build(config: trip.Trip, http: trip.Http, only: set[str], check_only: bool,
          chapter: Path | None) -> int:
    outputs: list[tuple[Path, str]] = []
    problems: list[str] = []
    if check_only and config.climate is None:
        raise trip.ConfigError(["--check: the configuration has no climate section"])
    if "temperatures" in only and config.climate is None:
        trip.log("temperatures skipped: the configuration has no climate section")
    elif "temperatures" in only:
        data = fetch_climate(config, http)
        if not check_only:
            for lang in config.languages:
                path = config.output(config.paths.images, "weather-temperatures", lang, ".png")
                outputs.append((path, trip.save_png(chart_temperatures(config, data, lang), path)))
                table = config.output(config.paths.images, "weather-temperatures", lang, ".md")
                outputs.append((table, trip.write_text(table, table_document(config, data, lang))))
        chapter = chapter or config.climate.chapter
        if chapter is not None:
            problems += check_chapters(config, data, chapter)
        elif check_only:
            raise trip.ConfigError(["--check: name the chapter with climate.chapter or --chapter"])
    if not check_only:
        if "daylight" in only:
            for lang in config.languages:
                path = config.output(config.paths.images, "daylight", lang, ".png")
                outputs.append((path, trip.save_png(chart_daylight(config, lang), path)))
        if "calendar" in only and config.calendar is None:
            trip.log("calendar skipped: the configuration has no calendar section")
        elif "calendar" in only:
            for lang in config.languages:
                path = config.output(config.paths.images, "trip-calendar", lang, ".png")
                outputs.append((path, trip.save_png(chart_calendar(config, lang), path)))
        if "plan-b" in only and config.plan_b is None:
            trip.log("plan-b skipped: the configuration has no plan_b section")
        elif "plan-b" in only:
            outline = trip.country_outline(http, config.country) if config.country else None
            for lang in config.languages:
                path = config.output(config.paths.images, "plan-b-regions", lang, ".png")
                outputs.append((path, trip.save_png(chart_plan_b(config, lang, outline), path)))
    for path, digest in outputs:
        trip.print_output(path, digest)
    for problem in problems:
        print(problem)
    if problems:
        trip.log(f"{len(problems)} difference{'' if len(problems) == 1 else 's'} between the "
                 "chapter and the computed table")
    return trip.EXIT_CHECK if problems else trip.EXIT_OK


def main(argv: list[str] | None = None) -> int:
    trip.configure_console()
    parser = trip.argument_parser(__doc__.split("\n")[0], USAGE)
    parser.add_argument("config", help="trip configuration (YAML); paths are relative to it")
    parser.add_argument("--only", nargs="+", choices=CHARTS, metavar="CHART",
                        help=f"build only these charts: {', '.join(CHARTS)}")
    parser.add_argument("--check", action="store_true",
                        help="only re-check the chapter's temperature table; draw nothing")
    parser.add_argument("--chapter", type=Path,
                        help="chapter to check instead of climate.chapter (twins name.<lang>.md "
                             "are checked too)")
    parser.add_argument("--offline", action="store_true",
                        help="use cached downloads only; fail with exit code 3 when one is missing")
    args = parser.parse_args(argv)
    only = {"temperatures"} if args.check else set(args.only or CHARTS)
    return trip.run(args.config, args.offline,
                    lambda config, http: build(config, http, only, args.check, args.chapter))


if __name__ == "__main__":
    raise SystemExit(main())
