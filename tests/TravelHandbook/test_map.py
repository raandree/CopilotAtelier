"""Route map with locator inset, elevation profile, and GPX export."""
from __future__ import annotations

import hashlib
import xml.etree.ElementTree as ET

import pytest
from PIL import Image

import build_map
import trip
from synthetic import FIXTURES, MINIMAL, FakeResponse

GPX = {"g": "http://www.topografix.com/GPX/1/1"}
OUTPUTS = ("route-map.png", "route-map.de.png", "elevation-profile.png",
           "elevation-profile.de.png")
MY_MAPS = MINIMAL + "route:\n  my_maps: synthetic-id\n"
TRACK = """\
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="synthetic" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="45.905" lon="7.080"><ele>1420</ele></trkpt>
    {point}
  </trkseg></trk>
</gpx>
"""


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_attribution_is_exact():
    assert trip.ATTRIBUTION == ("Map data © OpenStreetMap contributors, SRTM · "
                                "Map style © OpenTopoMap (CC-BY-SA)")


def test_kml_segments_are_numbered_with_the_unnumbered_one_first():
    segments = build_map.parse_kml((FIXTURES / "segments.kml").read_bytes())

    assert list(segments) == [1, 2, 3]
    assert segments[1][0] == (7.080, 45.905, 1420.0)
    assert segments[2][-1] == (7.152, 45.946, 2870.0)
    assert len(segments[3]) == 3


def test_gpx_segments_are_numbered_in_file_order():
    segments = build_map.parse_gpx((FIXTURES / "example-route.gpx").read_bytes())

    assert list(segments) == [1, 2, 3]
    assert [len(points) for points in segments.values()] == [9, 13, 5]
    assert segments[1][0] == (7.08, 45.905, 1420.0)


def test_my_maps_are_read_as_kml():
    assert build_map.my_maps_url("synthetic-id") == (
        "https://www.google.com/maps/d/kml?mid=synthetic-id&forcekml=1")


def test_longitude_span_follows_the_axes_aspect_ratio():
    lat_min, lat_max, zoom, aspect = 45.8, 46.0, 12, 1.6

    span = trip.lon_span(lat_min, lat_max, zoom, aspect)

    height = trip.to_px(7.0, lat_min, zoom)[1] - trip.to_px(7.0, lat_max, zoom)[1]
    width = trip.to_px(7.0 + span, 45.9, zoom)[0] - trip.to_px(7.0, 45.9, zoom)[0]
    assert width / height == pytest.approx(aspect)
    assert trip.lon_span(lat_min, lat_max, zoom + 1, aspect) == pytest.approx(span)


def test_label_overlaps_are_detected_and_printed(capsys):
    plt = trip.pyplot()
    fig = plt.figure(figsize=(4, 3), dpi=100)
    ax = fig.add_axes((0, 0, 1, 1))
    first = ax.text(0.40, 0.5, "Alpha Village")
    second = ax.text(0.45, 0.5, "Bravo Hut")
    far = ax.text(0.05, 0.05, "Charlie")

    found = trip.report_overlaps(fig, [("label alpha", first), ("label bravo", second),
                                       ("label charlie", far)], "de")
    plt.close(fig)

    assert found == [("label alpha", "label bravo")]
    assert "[de] overlap: label alpha / label bravo" in capsys.readouterr().err


def test_map_and_profile_render_deterministically(example_copy, network, capsys):
    assert build_map.main([str(example_copy)]) == 0
    first = capsys.readouterr()
    images = example_copy.parent / "docs" / "images"
    hashes = {}
    for name in OUTPUTS:
        with Image.open(images / name) as image:
            assert image.mode == "P"
        hashes[name] = sha256(images / name)
        assert f"{hashes[name]}  " in first.out
    assert "[en]" in first.err and "[de]" in first.err
    assert "HTTP 429" in first.err
    assert network.hits["tiles"] > 0
    assert network.session.urls("nominatim") == [
        "https://nominatim.openstreetmap.org/search?country=Switzerland&polygon_geojson=1"
        "&polygon_threshold=0.01&format=json&limit=1"]
    agent = trip.load_config(example_copy).user_agent
    assert all(headers["User-Agent"] == agent for _, headers in network.session.calls)

    requests_before = len(network.session.calls)
    assert build_map.main([str(example_copy)]) == 0

    assert len(network.session.calls) == requests_before
    assert {name: sha256(images / name) for name in OUTPUTS} == hashes


def test_gpx_export_keeps_every_fourth_track_point(example_copy, network):
    assert build_map.main([str(example_copy)]) == 0

    root = ET.parse(example_copy.parent / "docs" / "maps" / "route.gpx").getroot()
    segments = root.findall(".//g:trkseg", GPX)
    assert [len(segment.findall("g:trkpt", GPX)) for segment in segments] == [3, 4]
    names = [element.text for element in root.findall("g:wpt/g:name", GPX)]
    assert any("Alpha Village" in name for name in names)
    descriptions = " ".join(element.text for element in root.findall("g:wpt/g:desc", GPX))
    assert "Alphadorf" in descriptions


def test_my_maps_route_is_downloaded_as_kml(write_config, network):
    config = write_config(MINIMAL + "route:\n  my_maps: synthetic-id\n  segments: [1, 3]\n")

    assert build_map.main([str(config)]) == 0

    assert network.session.urls("google.com") == [build_map.my_maps_url("synthetic-id")]
    root = ET.parse(config.parent / "docs" / "maps" / "route.gpx").getroot()
    assert len(root.findall(".//g:trkseg", GPX)) == 2


def test_missing_route_segment_is_a_configuration_error(write_config, network, capsys):
    config = write_config(MINIMAL + "route:\n  my_maps: synthetic-id\n  segments: [1, 9]\n")

    assert build_map.main([str(config)]) == 2
    assert "route.segments: segment 9 not found" in capsys.readouterr().err


@pytest.mark.parametrize("page", [
    b"<!DOCTYPE html><html><head><title>Sign in</title></head><body><form></form></body></html>",
    b'<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Before you continue</p></body></html>',
], ids=["html", "xhtml"])
def test_a_sign_in_page_is_refused_before_the_cache_keeps_it(write_config, network, capsys, page):
    config = write_config(MY_MAPS)
    network.queue("google.com", FakeResponse(200, page))

    assert build_map.main([str(config)]) == 2
    assert "shared publicly" in capsys.readouterr().err

    assert build_map.main([str(config)]) == 0  # sharing the map takes effect on the next run
    assert len(network.session.urls("google.com")) == 2


@pytest.mark.parametrize("coordinates", ["7.080,north,1420", "7.080", "nan,45.905,1420",
                                         "7.080,95.0,1420", "7.080,45.905,high"])
def test_a_malformed_kml_coordinate_is_a_configuration_error(write_config, network, capsys,
                                                            coordinates):
    kml = (FIXTURES / "segments.kml").read_bytes().replace(
        b"7.080,45.905,1420 7.095", coordinates.encode("ascii") + b" 7.095")
    config = write_config(MY_MAPS)
    network.queue("google.com", FakeResponse(200, kml))

    assert build_map.main([str(config)]) == 2
    err = capsys.readouterr().err
    assert "route.my_maps" in err and repr(coordinates) in err

    assert build_map.main([str(config)]) == 0  # the corrected map is read on the next run


@pytest.mark.parametrize("point", [
    '<trkpt lat="north" lon="7.095"/>',
    '<trkpt lon="7.095"/>',
    '<trkpt lat="45.912" lon="7.095"><ele>high</ele></trkpt>',
    '<trkpt lat="45.912" lon="inf"/>',
    '<trkpt lat="-91" lon="7.095"/>',
])
def test_a_malformed_gpx_coordinate_is_a_configuration_error(write_config, tmp_path, network,
                                                            capsys, point):
    (tmp_path / "track.gpx").write_text(TRACK.format(point=point), encoding="utf-8")
    config = write_config(MINIMAL + "route:\n  gpx: track.gpx\n")

    assert build_map.main([str(config)]) == 2
    err = capsys.readouterr().err
    assert "route.gpx: segment 1, point 2" in err
