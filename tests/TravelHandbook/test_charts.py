"""Charts: per-night temperatures with the chapter check, daylight, calendar, Plan B regions."""
from __future__ import annotations

import hashlib
import json
import re
from datetime import date, timedelta

import pytest
from PIL import Image

import build_charts
import trip
from synthetic import SYNTHETIC_DEM, FakeResponse

CHARTS = ("weather-temperatures", "daylight", "trip-calendar", "plan-b-regions")
WEEK = [f"2020-07-{day:02d}" for day in range(1, 8)]  # the example's climate window: 7 days


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_window_statistics():
    daily = {"time": [f"2020-07-{day:02d}" for day in range(1, 11)],
             "temperature_2m_min": [-5, -3, -1, 1, 3, 5, 7, 9, 11, 13],
             "temperature_2m_max": [10, 11, 12, 13, 14, 15, 16, 17, 18, 19]}

    stats = build_charts.window_stats(daily)

    assert stats.night == pytest.approx(4.0)
    assert stats.day == pytest.approx(14.5)
    assert stats.cold == pytest.approx(-3.2)
    assert stats.lowest == -5


def test_one_request_per_year_and_place_with_cache_reuse(example_copy, network):
    config = trip.load_config(example_copy)

    climate = build_charts.fetch_climate(config, trip.Http(config.user_agent, config.paths.cache))

    archive = network.session.urls("archive-api.open-meteo.com")
    assert len(archive) == len(config.climate.places) * config.climate.years
    years = range(climate.last_year - config.climate.years + 1, climate.last_year + 1)
    for url in archive:
        start = re.search(r"start_date=(\d{4})-07-01", url)
        end = re.search(r"end_date=(\d{4})-07-07", url)
        assert start and end and start.group(1) == end.group(1)
        assert int(start.group(1)) in years
        assert "elevation=" in url
    assert set(climate.stats) == set(config.climate.places)

    build_charts.fetch_climate(config, trip.Http(config.user_agent, config.paths.cache))

    assert len(network.session.urls("archive-api.open-meteo.com")) == len(archive)


def test_archive_requests_ask_for_era5_alone(example_copy, network):
    # Open-Meteo's default blend ran about 5 degrees warmer at night than a valley
    # station's normals in a three-year comparison; ERA5 alone came within about 1.
    config = trip.load_config(example_copy)

    build_charts.fetch_climate(config, trip.Http(config.user_agent, config.paths.cache))

    archive = network.session.urls("archive-api.open-meteo.com")
    assert archive
    for url in archive:
        assert "models=era5" in url


@pytest.mark.parametrize("answer", [
    pytest.param({"daily": {"time": WEEK, "temperature_2m_max": [20.0, None, 21.0, 20.5, 19.0,
                                                                 18.0, 22.0],
                            "temperature_2m_min": [8.0] * 7}}, id="a null day"),
    pytest.param({"daily": {"time": WEEK[:5], "temperature_2m_max": [20.0] * 5,
                            "temperature_2m_min": [8.0] * 5}}, id="days missing"),
    pytest.param({"latitude": 45.9, "longitude": 7.1}, id="no daily data"),
])
def test_an_incomplete_year_fails_and_stays_out_of_the_cache(example_copy, network, answer):
    network.queue("archive-api.open-meteo.com",
                  FakeResponse(200, json.dumps(answer).encode("utf-8")))
    config = trip.load_config(example_copy)
    http = trip.Http(config.user_agent, config.paths.cache)

    with pytest.raises(trip.NetworkError) as caught:
        build_charts.fetch_climate(config, http)

    first = network.session.urls("archive-api.open-meteo.com")[0]
    place = config.climate.places[0]
    assert f"places.{place}:" in str(caught.value)
    assert "of 7 days" in str(caught.value)
    assert not http.cache_file(first).exists()

    build_charts.fetch_climate(config, http)  # a later run asks again and gets every day

    assert network.session.urls("archive-api.open-meteo.com").count(first) == 2


def test_an_incomplete_year_exits_with_the_network_code(example_copy, network, capsys):
    answer = {"daily": {"time": WEEK, "temperature_2m_max": [20.0] * 6 + [None],
                        "temperature_2m_min": [8.0] * 6 + [None]}}
    network.queue("archive-api.open-meteo.com", FakeResponse(200, json.dumps(answer).encode()))

    assert build_charts.main([str(example_copy), "--only", "temperatures"]) == 3
    assert "6 of 7 days" in capsys.readouterr().err


def _overlap(first, second, pad=0.5):
    return (first.x0 < second.x1 - pad and second.x0 < first.x1 - pad
            and first.y0 < second.y1 - pad and second.y0 < first.y1 - pad)


def test_temperature_labels_cover_no_bar_whisker_or_label(example_copy):
    # A dense trek: 24 nights in blocks of three alike, alternating warm valleys and
    # frozen high camps, the layout that hid degree signs behind the next bar and
    # crossed altitude labels.
    config = trip.load_config(example_copy)
    keys = list(config.places)
    start = date(2026, 11, 19)
    config.nights = [trip.Night(start + timedelta(days=index), keys[(index // 3) % len(keys)])
                     for index in range(24)]
    stats, heights = {}, {}
    for index, key in enumerate(keys):
        high = index % 2 == 1
        stats[key] = build_charts.Stats(night=-9.0 if high else 8.0, day=2.0 if high else 20.0,
                                        cold=-14.0 if high else 6.0, lowest=-20.0 if high else 3.0)
        heights[key] = 4050.0 if high else 1305.0
    data = build_charts.ClimateData(stats, heights, [], 2016, 2025,
                                    (start, start + timedelta(days=23)))

    figure = build_charts.chart_temperatures(config, data, "de")
    figure.canvas.draw()
    renderer = figure.canvas.get_renderer()
    axes = figure.axes[0]
    labels = [(round(text.xy[0]), text.get_text(), text.get_window_extent(renderer))
              for text in axes.texts if text.get_text()]
    bars = [(round(bar.get_x() + bar.get_width() / 2), bar.get_window_extent(renderer))
            for bar in axes.patches if bar.get_width() == pytest.approx(build_charts.BAR_WIDTH)]
    whiskers = [(round(line.get_xdata()[0]), line.get_window_extent(renderer))
                for line in axes.lines if len(set(line.get_xdata())) == 1]

    problems = []
    for night, text, box in labels:
        problems += [f"{text!r} of night {night} covers the bar of night {other}"
                     for other, bar in bars if other != night and _overlap(box, bar)]
        problems += [f"{text!r} of night {night} crosses the whisker of night {other}"
                     for other, line in whiskers if _overlap(box, line)]
    for index, (night, text, box) in enumerate(labels):
        problems += [f"{text!r} of night {night} overlaps {other_text!r} of night {other}"
                     for other, other_text, other_box in labels[index + 1:]
                     if _overlap(box, other_box)]
    assert problems == []


def test_missing_elevation_comes_from_the_elevation_model(example_copy, network, capsys):
    config = trip.load_config(example_copy)
    assert config.places["charlie_lake"].elevation is None

    climate = build_charts.fetch_climate(config, trip.Http(config.user_agent, config.paths.cache))

    assert climate.elevations["charlie_lake"] == SYNTHETIC_DEM
    assert network.session.urls("api.open-meteo.com/v1/elevation") == [
        "https://api.open-meteo.com/v1/elevation?latitude=45.962&longitude=7.108"]
    assert "Copernicus GLO-90" in capsys.readouterr().err


def test_daylight_uses_the_configured_time_zone(example_copy):
    config = trip.load_config(example_copy)

    rows = build_charts.daylight_rows(config)

    assert len(rows) == len(config.nights)
    for row in rows:
        assert row.dawn < row.sunrise < row.sunset < row.dusk
        assert row.sunrise.utcoffset().total_seconds() == 2 * 3600
        assert 5 <= row.sunrise.hour <= 6 and 20 <= row.sunset.hour <= 21


def test_daylight_chart_notes_the_flat_horizon():
    assert "flat horizon" in trip.DEFAULT_LABELS["en"]["daylight_note"]


def test_temperature_tables_and_the_chapter_check(example_copy, network, capsys):
    assert build_charts.main([str(example_copy), "--only", "temperatures"]) == 1
    assert "not found" in capsys.readouterr().out
    images = example_copy.parent / "docs" / "images"
    english = (images / "weather-temperatures.md").read_text(encoding="utf-8")
    german = (images / "weather-temperatures.de.md").read_text(encoding="utf-8")
    assert english.splitlines()[0].startswith("| Date | Place |")
    assert german.splitlines()[0].startswith("| Datum | Ort |")
    assert re.search(r"\| \u2212?\d+,\d \|", german)
    docs = example_copy.parent / "docs"
    (docs / "weather.md").write_text("# Weather\n\n" + english, encoding="utf-8")
    (docs / "weather.de.md").write_text("# Wetter\n\n" + german, encoding="utf-8")

    assert build_charts.main([str(example_copy), "--check"]) == 0
    capsys.readouterr()

    lines = german.splitlines()
    cells = lines[2].split("|")
    cells[4] = " 99,9 "
    changed = "\n".join(lines[:2] + ["|".join(cells)] + lines[3:]) + "\n"
    (docs / "weather.de.md").write_text("# Wetter\n\n" + changed, encoding="utf-8")

    assert build_charts.main([str(example_copy), "--check"]) == 1
    out = capsys.readouterr().out
    assert "weather.de.md" in out
    assert f"{cells[1].strip()} | {cells[2].strip()}" in out


def test_all_charts_render_deterministically(example_copy, network, capsys):
    build_charts.main([str(example_copy)])
    images = example_copy.parent / "docs" / "images"
    docs = example_copy.parent / "docs"
    for suffix in ("", ".de"):
        table = (images / f"weather-temperatures{suffix}.md").read_text(encoding="utf-8")
        (docs / f"weather{suffix}.md").write_text(table, encoding="utf-8")
    pngs = [images / f"{name}{suffix}.png" for name in CHARTS for suffix in ("", ".de")]
    hashes = {}
    for path in pngs:
        with Image.open(path) as image:
            assert image.mode == "P"
        hashes[path] = sha256(path)
    capsys.readouterr()
    requests_before = len(network.session.calls)

    assert build_charts.main([str(example_copy)]) == 0

    out = capsys.readouterr()
    assert len(network.session.calls) == requests_before
    assert {path: sha256(path) for path in pngs} == hashes
    for digest in hashes.values():
        assert f"{digest}  " in out.out
    assert "HTTP 429" in out.err
