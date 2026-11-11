# /// script
# requires-python = ">=3.11"
# dependencies = ["matplotlib>=3.8", "pillow>=10.3", "requests>=2.32.4", "ruamel.yaml>=0.18", "tzdata"]
# ///
"""Build the route map, the elevation profile, and the GPX export of a trip.

The route map draws OpenTopoMap tiles, the GPS track (a GPX file, or a Google
My Maps map read as KML), planned variants, day hikes, and transfers, every
night's stop numbered by night, the highest point of each day, a locator inset
with the country outline from Nominatim, and a night-by-night panel. It writes
one PNG per language (route-map.png, route-map.<lang>.png), the elevation
profile likewise (elevation-profile.png, ...), and one GPX file for OsmAnd or
Organic Maps that keeps every fourth track point.
"""
from __future__ import annotations

import math
import re
import sys
import xml.etree.ElementTree as ET
from datetime import timedelta
from xml.sax.saxutils import escape

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.dates import date2num  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Rectangle  # noqa: E402
from matplotlib.ticker import FuncFormatter  # noqa: E402
from PIL import Image  # noqa: E402

sys.dont_write_bytecode = True  # an installed Skill folder must not collect __pycache__
import trip  # noqa: E402

USAGE = """example (from the repository root):
  uv run skills/travel-handbook/scripts/build_map.py handbook/trip.yaml

stdout: "<sha256>  <path>" per output, so a rebuild can be proven identical.
stderr: label overlaps per language, retries, and the HTTP summary with the
count of HTTP 429 answers."""

TILE_URL = "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png"
TILE_MIRRORS = "abc"  # OpenTopoMap's three mirrors, chosen per tile so cache keys stay stable
TILE_PAUSE = 0.2  # seconds between tile downloads: polite to a volunteer-run server
TILE_BACKOFF = 5.0  # seconds, times the attempt number, after a refused tile
MAX_TILES = 300  # tiles per map; more means the zoom is too high for the extent
MY_MAPS_KML = "https://www.google.com/maps/d/kml"
KML = {"k": "http://www.opengis.net/kml/2.2"}
KML_ROOT = f"{{{KML['k']}}}kml"  # the root element of a KML 2.2 document, as My Maps exports it
GPX_NAMESPACE = "http://www.topografix.com/GPX/1/1"
SEGMENT_NUMBER = re.compile(r"\((\d+)\)\s*$")
GPX_EVERY = 4  # keep every fourth track point: small enough for phone apps, shape intact
MIN_SPAN = 0.05  # degrees: a single place still gets about 5 km of surroundings

MAP_HEIGHT = 9.0  # inches of map: 900 px, about one laptop screen
TITLE_BAND = 0.7  # inches above the map for the title
HEAD_BASELINE = 0.3  # inches from the panel top down to the heading's baseline
PANEL_HEAD = 0.62  # inches from the panel top down to the first line's baseline
PANEL_ROW = 0.27  # inches per panel line: 10-point text with leading
PANEL_FOOT = 0.2  # inches of blank space under the panel
PANEL_ROWS = 8  # nights per panel column before the next column starts
PANEL_COLUMNS = 4  # columns that fit the 16-inch width
PANEL_COLUMN = 3.95  # inches per panel column: four of them fill the width
DATE_X = 0.4  # inches from the column start to the date: room for "12."
NAME_X = 1.3  # inches from the column start to the place name: room for the longest date
ELEVATION_X = 3.8  # inches from the column start to the right edge of the elevation
SIDE = 0.01  # share of the figure width left blank on each side
INSET_SIZE = (0.29, 0.36)  # locator inset width and height as shares of the map
INSET_CORNERS = (  # candidate corners in map-axes fractions, tried in this order
    ((0.70, 0.62), "NE"),  # top right
    ((0.01, 0.62), "NW"),  # top left
    ((0.70, 0.05), "SE"),  # bottom right, above the attribution
)
LOCATOR_MARGIN = 0.06  # share of the country's size kept around its outline
ATTRIBUTION_AT = (0.995, 0.005)  # map-axes fraction of the attribution's lower right corner
PROFILE_HEIGHT = 6.4  # inches: 640 px, wide and short for a dated axis
PROFILE_HEADROOM = 1.15  # top of the profile axis above the highest point: room for labels
PROFILE_STEP = 500  # metres: the profile axis ends on a multiple of this
STOP_SIZE = 15  # points: a circle that holds a two-digit night number
STOP_SIZE_SHARED = 19  # points: a circle that holds two night numbers such as 4/5
HIGH_SIZE = 12  # points: the triangle of the highest point of a day
FONT_TITLE = 17  # points: figure titles
FONT_HEAD = 12.5  # points: panel headings
FONT_LABEL = 10  # points: place names and panel lines
FONT_STOP = 8  # points: night numbers inside the circles
FONT_SMALL = 8  # points: attribution, notes, and locator names
LINE_TRACK = 2.4  # points: the GPS track, the strongest line
LINE_VARIANT = 2.0  # points: planned variants and transfers
LINE_HIKE = 1.8  # points: day hikes

ROUTE = "#b03a2e"
HIGH = "#1f618d"
TRANSFER = "#616a6b"
INK = "#1c1c1c"
NOTE = "#5d6d7e"
SEA = "#e8edf1"
LAND = "#fbf8f1"
BORDER = "#6e6e6e"


def my_maps_url(map_id: str) -> str:
    """Google My Maps exports any public map as KML at this address."""
    return trip.build_url(MY_MAPS_KML, {"mid": map_id, "forcekml": 1})


def _point(lon: str | None, lat: str | None,
           ele: str | None = None) -> tuple[float, float, float | None] | None:
    """Degrees and metres of a track point; None when a value is missing or impossible."""
    try:
        point = (float(lon), float(lat), None if ele is None else float(ele))
    except (TypeError, ValueError):
        return None
    if not all(math.isfinite(value) for value in point if value is not None):
        return None
    return point if -180 <= point[0] <= 180 and -90 <= point[1] <= 90 else None


def parse_kml(data: bytes) -> dict[int, list[tuple[float, float, float | None]]]:
    """Return the track segments of a My Maps KML export by their number.

    Segment names carry "(N)"; the one without a number is segment 1. An answer
    that is not KML, such as a sign-in or consent page, or a malformed coordinate
    is a configuration error.
    """
    try:
        root = ET.fromstring(data)
        problem = None if root.tag == KML_ROOT else f"its root element is {root.tag}"
    except ET.ParseError as error:
        problem = str(error)
    if problem is not None:
        raise trip.ConfigError([f"route.my_maps: the answer is not KML ({problem}); is the map "
                                "shared publicly?"])
    segments: dict[int, list[tuple[float, float, float | None]]] = {}
    for placemark in root.iterfind(".//k:Placemark", KML):
        lines = placemark.findall(".//k:LineString/k:coordinates", KML)
        if not lines:
            continue
        name = placemark.findtext("k:name", default="", namespaces=KML).strip()
        match = SEGMENT_NUMBER.search(name)
        number = int(match.group(1)) if match else 1
        if number in segments:
            raise trip.ConfigError([f"route.my_maps: two track segments carry number {number} "
                                    f"({name!r}); rename one in My Maps"])
        points = []
        for line in lines:
            for item in (line.text or "").split():
                values = item.split(",")
                point = _point(*values) if len(values) in (2, 3) else None
                if point is None:
                    raise trip.ConfigError([f"route.my_maps: segment {number} ({name!r}) has a "
                                            f"malformed coordinate {item!r}; fix it in My Maps"])
                points.append(point)
        segments[number] = points
    return dict(sorted(segments.items()))


def parse_gpx(data: bytes) -> dict[int, list[tuple[float, float, float | None]]]:
    """Return the track segments of a GPX file, numbered 1, 2, ... in file order."""
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise trip.ConfigError([f"route.gpx: not a valid GPX file ({error})"]) from None
    segments = {}
    for number, segment in enumerate(root.iterfind(".//{*}trkseg"), start=1):
        points = []
        for index, point in enumerate(segment.iterfind("{*}trkpt"), start=1):
            lon, lat, ele = point.get("lon"), point.get("lat"), point.findtext("{*}ele") or None
            parsed = _point(lon, lat, ele)
            if parsed is None:
                raise trip.ConfigError([f"route.gpx: segment {number}, point {index} has a "
                                        f"malformed coordinate (lat={lat!r}, lon={lon!r}, "
                                        f"ele={ele!r})"])
            points.append(parsed)
        segments[number] = points
    return segments


def load_track(config: trip.Trip, http: trip.Http) -> dict[int, list]:
    """The configured segments of the route, or nothing when there is no route."""
    route = config.route
    if route is None:
        return {}
    if route.gpx is not None:
        try:
            segments = parse_gpx(route.gpx.read_bytes())
        except OSError as error:
            raise trip.ConfigError([f"route.gpx: cannot read {trip.display_path(route.gpx)} "
                                    f"({error.strerror or error})"]) from None
    else:
        # parse_kml also checks the answer before the cache keeps it: a sign-in or consent page,
        # or a broken track, is refused, so the run after the map is fixed downloads it again.
        segments = parse_kml(http.get(my_maps_url(route.my_maps), check=parse_kml))
    if not segments:
        raise trip.ConfigError(["route: the track has no segments"])
    wanted = route.segments or list(segments)
    missing = [number for number in wanted if number not in segments]
    if missing:
        found = ", ".join(map(str, segments))
        raise trip.ConfigError([f"route.segments: segment {number} not found (the track has "
                                f"{found})" for number in missing])
    return {number: segments[number] for number in wanted}


class Layout:
    """Figure geometry of the route map: title band, map, night-by-night panel."""

    def __init__(self, nights: int) -> None:
        self.columns = max(1, min(PANEL_COLUMNS, math.ceil(nights / PANEL_ROWS)))
        self.rows = math.ceil(nights / self.columns)
        self.panel = PANEL_HEAD + self.rows * PANEL_ROW + PANEL_FOOT
        self.height = TITLE_BAND + MAP_HEIGHT + self.panel
        self.axes = (SIDE, self.panel / self.height, 1 - 2 * SIDE, MAP_HEIGHT / self.height)

    @property
    def axes_inches(self) -> tuple[float, float]:
        return trip.FIGURE_WIDTH * self.axes[2], MAP_HEIGHT


def best_zoom(lat_min: float, lat_max: float, target_px: float) -> int:
    """The zoom at which the latitude range is closest to the axes height in pixels."""
    height = trip.to_px(0, lat_min, 0)[1] - trip.to_px(0, lat_max, 0)[1]
    return max(1, min(trip.MAX_ZOOM, round(math.log2(target_px / height))))


def map_frame(config: trip.Trip, track: dict[int, list],
              axes_inches: tuple[float, float]) -> tuple[int, tuple[float, float, float, float]]:
    """Zoom and extent (lon_min, lat_min, lon_max, lat_max) of the main map.

    The longitude span always follows from the axes' aspect ratio at the zoom
    level; otherwise the tiles leave blank strips beside the map.
    """
    aspect = axes_inches[0] / axes_inches[1]
    excluded = set(config.map.exclude)
    route = config.route
    keys = [night.place for night in config.nights] + [high.place for high in config.high_points]
    if route is not None:
        keys += [key for chain in route.variants + route.day_hikes for key in chain]
    points = [(config.places[key].lon, config.places[key].lat)
              for key in dict.fromkeys(keys) if key not in excluded]
    points += [(lon, lat) for segment in track.values() for lon, lat, _ in segment]
    if not points:
        raise trip.ConfigError(["map.exclude: leaves no place to show on the main map"])
    xs, ys = zip(*(trip.to_px(lon, lat, 0) for lon, lat in points), strict=True)
    minimum = trip.TILE_SIZE * MIN_SPAN / 360
    width = max(max(xs) - min(xs), minimum) / (1 - 2 * config.map.margin)
    height = max(max(ys) - min(ys), minimum) / (1 - 2 * config.map.margin)
    if width / height > aspect:
        height = width / aspect
    centre_x, centre_y = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    lat_min = trip.from_px(centre_x, centre_y + height / 2, 0)[1]
    lat_max = trip.from_px(centre_x, centre_y - height / 2, 0)[1]
    lon_centre = trip.from_px(centre_x, centre_y, 0)[0]
    if config.map.lat is not None:
        lat_min, lat_max = config.map.lat
    if config.map.lon_center is not None:
        lon_centre = config.map.lon_center
    zoom = config.map.zoom or best_zoom(lat_min, lat_max, axes_inches[1] * trip.DPI)
    span = trip.lon_span(lat_min, lat_max, zoom, aspect)
    return zoom, (lon_centre - span / 2, lat_min, lon_centre + span / 2, lat_max)


def mosaic(http: trip.Http, zoom: int, bbox: tuple[float, float, float, float]):
    """Stitch the tiles that cover bbox; return the image, its pixel origin, and the crop."""
    size = trip.TILE_SIZE
    x0, y1 = trip.to_px(bbox[0], bbox[1], zoom)
    x1, y0 = trip.to_px(bbox[2], bbox[3], zoom)
    tx0, tx1, ty0, ty1 = int(x0 // size), int(x1 // size), int(y0 // size), int(y1 // size)
    count = (tx1 - tx0 + 1) * (ty1 - ty0 + 1)
    if count > MAX_TILES:
        raise trip.ConfigError([f"map.zoom: the map needs {count} tiles at zoom {zoom}; "
                                f"lower map.zoom (at most {MAX_TILES} tiles)"])
    image = Image.new("RGB", ((tx1 - tx0 + 1) * size, (ty1 - ty0 + 1) * size))
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            url = TILE_URL.format(s=TILE_MIRRORS[(tx + ty) % len(TILE_MIRRORS)], z=zoom,
                                  x=tx, y=ty)
            data = http.get(url, pause=TILE_PAUSE, backoff=TILE_BACKOFF, check=trip.image_answer)
            with trip.open_image(data) as tile:
                image.paste(tile.convert("RGB"), ((tx - tx0) * size, (ty - ty0) * size))
    origin = (tx0 * size, ty0 * size)
    return image, origin, (x0 - origin[0], y0 - origin[1], x1 - origin[0], y1 - origin[1])

def _chain_xy(config: trip.Trip, chain: list[str], project) -> tuple:
    return tuple(zip(*(project(config.places[key].lon, config.places[key].lat) for key in chain),
                     strict=True))


def draw_locator(inset, config: trip.Trip, lang: str, outline, bbox) -> None:
    """Country outline with the main map's area, the transfers, and excluded places."""
    inset.set_facecolor(SEA)
    for ring in outline:
        inset.fill(*zip(*(trip.mercator(lon, lat) for lon, lat in ring), strict=True), fc=LAND,
                   ec=BORDER, lw=1)
    extent = config.map.locator_extent or trip.outline_extent(outline, LOCATOR_MARGIN)
    x0, y0 = trip.mercator(extent[0], extent[1])
    x1, y1 = trip.mercator(extent[2], extent[3])
    inset.set_xlim(x0, x1)
    inset.set_ylim(y0, y1)
    inset.set_aspect("equal")
    inset.set_xticks([])
    inset.set_yticks([])
    bx0, by0 = trip.mercator(bbox[0], bbox[1])
    bx1, by1 = trip.mercator(bbox[2], bbox[3])
    inset.add_patch(Rectangle((bx0, by0), bx1 - bx0, by1 - by0, fc=ROUTE, alpha=0.25, ec=ROUTE,
                              lw=1.6))
    inset.annotate(config.text(lang, "map_area"), (bx0, by1), xytext=(-3, 3),
                   textcoords="offset points", ha="right", fontsize=FONT_SMALL, color=ROUTE,
                   fontweight="bold", path_effects=trip.halo(2.5))
    for chain in config.route.transfers if config.route else []:
        inset.plot(*_chain_xy(config, chain, trip.mercator), color=TRANSFER, lw=1.4, ls="--")
    for key in config.map.exclude:
        x, y = trip.mercator(config.places[key].lon, config.places[key].lat)
        inset.plot(x, y, "o", ms=4.5, color=INK)
        inset.annotate(config.name(key, lang), (x, y), xytext=(5, -4), textcoords="offset points",
                       fontsize=FONT_SMALL, fontweight="bold", path_effects=trip.halo(2.5))
    for label in config.map.locator_labels:
        inset.text(*trip.mercator(label.lon, label.lat), label.text[lang], fontsize=FONT_SMALL,
                   color=BORDER, fontweight="bold", ha="center")


def draw_panel(fig, config: trip.Trip, lang: str, layout: Layout) -> list:
    """The night-by-night list under the map; returns its texts for the overlap check."""
    texts = []

    def put(x_inches: float, y_inches: float, text: str, size: float = FONT_LABEL,
            **options) -> None:
        texts.append((f"label panel {len(texts)}",
                      fig.text(x_inches / trip.FIGURE_WIDTH, y_inches / layout.height, text,
                               fontsize=size, **options)))

    left = SIDE * trip.FIGURE_WIDTH
    put(left, layout.panel - HEAD_BASELINE, config.text(lang, "map_panel"), size=FONT_HEAD,
        fontweight="bold")
    for index, night in enumerate(config.nights):
        column, row = divmod(index, layout.rows)
        x = left + column * PANEL_COLUMN
        y = layout.panel - PANEL_HEAD - row * PANEL_ROW
        place = config.places[night.place]
        put(x, y, f"{index + 1}.", fontweight="bold")
        put(x + DATE_X, y, config.date_text(lang, night.date))
        put(x + NAME_X, y, place.names[lang])
        if place.elevation is not None:
            put(x + ELEVATION_X, y, config.elevation_text(lang, place.elevation), ha="right")
    return texts


def inset_corner(config: trip.Trip, track: dict[int, list], project, crop) -> tuple:
    """The candidate corner for the locator inset that covers the fewest map points."""
    points = [project(place.lon, place.lat) for place in config.places.values()]
    points += [project(lon, lat) for segment in track.values() for lon, lat, _ in segment]
    fractions = [((x - crop[0]) / (crop[2] - crop[0]), (crop[3] - y) / (crop[3] - crop[1]))
                 for x, y in points]

    def covered(corner: tuple) -> int:
        (left, bottom), _ = corner
        return sum(left <= fx <= left + INSET_SIZE[0] and bottom <= fy <= bottom + INSET_SIZE[1]
                   for fx, fy in fractions)

    return min(INSET_CORNERS, key=covered)


def draw_map(config: trip.Trip, lang: str, layout: Layout, frame, tiles, track, outline):
    """Draw the route map for one language; return the figure and its overlap items."""
    zoom, bbox = frame
    image, origin, crop = tiles
    fig = plt.figure(figsize=(trip.FIGURE_WIDTH, layout.height), dpi=trip.DPI)
    ax = fig.add_axes(layout.axes)
    ax.imshow(image, extent=(0, image.width, image.height, 0), interpolation="lanczos")
    ax.set_xlim(crop[0], crop[2])
    ax.set_ylim(crop[3], crop[1])
    ax.set_axis_off()

    def xy(lon: float, lat: float) -> tuple[float, float]:
        x, y = trip.to_px(lon, lat, zoom)
        return x - origin[0], y - origin[1]

    route = config.route
    legend = []
    for points in track.values():
        ax.plot(*zip(*(xy(lon, lat) for lon, lat, _ in points), strict=True), color=ROUTE,
                lw=LINE_TRACK, solid_capstyle="round", path_effects=trip.halo(4.5), zorder=3)
    if track:
        legend.append(Line2D([], [], color=ROUTE, lw=LINE_TRACK, label=config.text(lang, "map_track")))
    styles = (("variants", "map_variant", ROUTE, LINE_VARIANT, (0, (5, 3))),
              ("day_hikes", "map_day_hike", ROUTE, LINE_HIKE, (0, (1, 2))),
              ("transfers", "map_transfer", TRANSFER, LINE_VARIANT, "--"))
    for kind, label, colour, width, style in styles:
        chains = getattr(route, kind) if route else []
        for chain in chains:
            ax.plot(*_chain_xy(config, chain, xy), color=colour, lw=width, ls=style,
                    path_effects=trip.halo(width + 2), zorder=3)
        if chains:
            legend.append(Line2D([], [], color=colour, lw=width, ls=style,
                                 label=config.text(lang, label)))

    labels, markers = [], []
    excluded = set(config.map.exclude)
    for key, numbers in config.night_numbers().items():
        if key in excluded:
            continue
        place = config.places[key]
        x, y = xy(place.lon, place.lat)
        size = STOP_SIZE if len(numbers) == 1 else STOP_SIZE_SHARED
        ax.plot(x, y, "o", ms=size, mfc="white", mec=INK, mew=1.6, zorder=5)
        ax.text(x, y, "/".join(map(str, numbers)), ha="center", va="center", zorder=6,
                fontsize=FONT_STOP if len(numbers) == 1 else FONT_STOP - 1, fontweight="bold")
        markers.append((f"marker {key}", lambda x=x, y=y, size=size: trip.marker_box(ax, x, y, size)))
        dx, dy, align = place.label or (*trip.LABEL_OFFSET, "left")
        labels.append((f"label {key}", ax.annotate(
            place.names[lang], (x, y), xytext=(dx, dy), textcoords="offset pixels", ha=align,
            va="center", fontsize=FONT_LABEL, fontweight="bold", color=INK,
            path_effects=trip.halo(), zorder=7)))
    legend.append(Line2D([], [], ls="", marker="o", ms=11, mfc="white", mec=INK,
                         label=config.text(lang, "map_stop")))
    for high in config.high_points:
        place = config.places[high.place]
        if high.place in excluded:
            continue
        x, y = xy(place.lon, place.lat)
        ax.plot(x, y, "^", ms=HIGH_SIZE, mfc=HIGH, mec="white", mew=1.5, zorder=5)
        markers.append((f"marker {high.place}",
                        lambda x=x, y=y: trip.marker_box(ax, x, y, HIGH_SIZE)))
        text = place.names[lang] + (f" {config.elevation_text(lang, place.elevation)}"
                                    if place.elevation is not None else "")
        dx, dy, align = place.label or (*trip.LABEL_OFFSET, "left")
        labels.append((f"label {high.place}", ax.annotate(
            text, (x, y), xytext=(dx, dy), textcoords="offset pixels", ha=align, va="center",
            fontsize=FONT_LABEL - 0.5, fontweight="bold", color=HIGH,
            path_effects=trip.halo(), zorder=7)))
    if config.high_points:
        legend.append(Line2D([], [], ls="", marker="^", ms=11, mfc=HIGH, mec="white",
                             label=config.text(lang, "map_high")))

    box = ax.legend(handles=legend, loc="lower left", fontsize=FONT_LABEL - 0.5, framealpha=0.9)
    credit = trip.ATTRIBUTION
    if route is not None and route.credit:
        credit += f" · {route.credit[lang]}"
    attribution = ax.text(*ATTRIBUTION_AT, credit, transform=ax.transAxes, ha="right",
                          va="bottom", fontsize=FONT_SMALL,
                          bbox={"fc": "white", "ec": "none", "alpha": 0.8, "pad": 2})
    areas = [("legend", box), ("attribution", attribution)]
    if outline:
        (left, bottom), anchor = inset_corner(config, track, xy, crop)
        inset = ax.inset_axes((left, bottom, *INSET_SIZE))
        draw_locator(inset, config, lang, outline, bbox)
        inset.set_anchor(anchor)
        areas.append(("locator", inset))
    fig.text(SIDE, 1 - (TITLE_BAND / 2) / layout.height, config.text(lang, "map_title"),
             fontsize=FONT_TITLE, fontweight="bold", va="center")
    labels += draw_panel(fig, config, lang, layout)
    return fig, labels + markers + areas


def draw_profile(config: trip.Trip, lang: str):
    """Sleeping elevation by night with the highest point of each day; None without data.

    A night whose place has no elevation leaves a gap in the line rather than
    a straight line that would suggest an elevation.
    """
    nights = [night for night in config.nights
              if config.places[night.place].elevation is not None]
    if not nights:
        return None
    fig, ax = plt.subplots(figsize=(trip.FIGURE_WIDTH, PROFILE_HEIGHT), dpi=trip.DPI)
    sleep = {night.date: config.places[night.place].elevation for night in nights}
    heights = [sleep.get(night.date, math.nan) for night in config.nights]
    ax.plot([night.date for night in config.nights], heights, color=ROUTE, lw=LINE_TRACK,
            marker="o", ms=7, mfc="white", mec=ROUTE, mew=2,
            label=config.text(lang, "profile_sleep"), zorder=4)
    tops = list(sleep.values())
    for high in config.high_points:
        place = config.places[high.place]
        if place.elevation is None:
            continue
        tops.append(place.elevation)
        if high.date in sleep:
            ax.plot([high.date, high.date], [sleep[high.date], place.elevation], color=HIGH,
                    lw=1.4, ls=":")
        ax.plot(high.date, place.elevation, "^", ms=11, color=HIGH, zorder=5)
        ax.annotate(f"{place.names[lang]}\n{config.elevation_text(lang, place.elevation)}",
                    (high.date, place.elevation), xytext=(0, 9), textcoords="offset points",
                    ha="center", fontsize=FONT_LABEL - 1, color=HIGH, fontweight="bold",
                    path_effects=trip.halo())
    if any(config.places[high.place].elevation is not None for high in config.high_points):
        ax.plot([], [], "^", ms=10, color=HIGH, label=config.text(lang, "map_high"))
    first, last = config.nights[0].date, config.nights[-1].date
    days = [first + timedelta(days=offset) for offset in range((last - first).days + 1)]
    where = {night.date: night.place for night in config.nights}
    ax.set_xticks(days)
    ax.set_xticklabels([f"{config.date_text(lang, day)}  {config.name(where[day], lang)}"
                        if day in where else config.date_text(lang, day) for day in days],
                       rotation=45, ha="right", rotation_mode="anchor", fontsize=FONT_LABEL - 1)
    ax.set_xlim(date2num(first) - 0.5, date2num(last) + 0.5)  # half a day of room each side
    top = math.ceil(max(tops) * PROFILE_HEADROOM / PROFILE_STEP) * PROFILE_STEP
    ax.set_ylim(0, top)
    ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: config.number(lang, value)))
    ax.set_ylabel(config.text(lang, "profile_axis"))
    ax.grid(axis="y", color="#e5e7e9")
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    fig.text(trip.TEXT_X, trip.TITLE_Y, config.text(lang, "profile_title"),
             fontsize=FONT_TITLE - 3, fontweight="bold", va="top")
    ax.legend(loc="lower left", bbox_to_anchor=(0, 1), ncol=2, frameon=False,
              fontsize=FONT_LABEL - 0.5)
    fig.text(trip.TEXT_X, trip.NOTE_Y, config.text(lang, "profile_note"), fontsize=FONT_SMALL,
             color=NOTE)
    fig.tight_layout(rect=trip.CHART_AREA)
    return fig


def _describe(config: trip.Trip, lang: str, key: str, dates: list) -> str:
    place = config.places[key]
    parts = [place.names[lang], ", ".join(config.date_text(lang, day) for day in dates)]
    if place.elevation is not None:
        parts.append(config.elevation_text(lang, place.elevation))
    return " · ".join(parts)


def write_gpx(config: trip.Trip, track: dict[int, list]) -> str:
    """Waypoints for every night's place and high point, plus the decimated track."""
    primary = config.primary
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             f'<gpx version="1.1" creator="travel-handbook build_map.py" '
             f'xmlns="{GPX_NAMESPACE}">']
    if config.title:
        title = " / ".join(dict.fromkeys(config.title[lang] for lang in config.languages))
        lines.append(f"  <metadata><name>{escape(title)}</name></metadata>")

    def waypoint(key: str, name: str, dates: list) -> str:
        place = config.places[key]
        ele = f"<ele>{place.elevation:.0f}</ele>" if place.elevation is not None else ""
        desc = " / ".join(_describe(config, lang, key, dates) for lang in config.languages)
        return (f'  <wpt lat="{place.lat}" lon="{place.lon}">{ele}<name>{escape(name)}</name>'
                f"<desc>{escape(desc)}</desc></wpt>")

    dates: dict[str, list] = {}
    for night in config.nights:
        dates.setdefault(night.place, []).append(night.date)
    for key, numbers in config.night_numbers().items():
        name = f"N{'/'.join(map(str, numbers))} {config.name(key, primary)}"
        lines.append(waypoint(key, name, dates[key]))
    for high in config.high_points:
        lines.append(waypoint(high.place, f"▲ {config.name(high.place, primary)}", [high.date]))
    if track:
        name = " / ".join(dict.fromkeys(config.text(lang, "map_track") for lang in config.languages))
        lines.append(f"  <trk><name>{escape(name)}</name>")
        for points in track.values():
            lines.append("    <trkseg>")
            for lon, lat, ele in points[::GPX_EVERY]:
                height = f"<ele>{ele:.0f}</ele>" if ele is not None else ""
                lines.append(f'      <trkpt lat="{lat:.6f}" lon="{lon:.6f}">{height}</trkpt>')
            lines.append("    </trkseg>")
        lines.append("  </trk>")
    lines.append("</gpx>")
    return trip.write_text(config.paths.gpx, "\n".join(lines) + "\n")


def build(config: trip.Trip, http: trip.Http, languages: list[str]) -> int:
    track = load_track(config, http)
    outline = trip.country_outline(http, config.country) if config.country else None
    layout = Layout(len(config.nights))
    frame = map_frame(config, track, layout.axes_inches)
    tiles = mosaic(http, *frame)
    outputs = []
    for lang in languages:
        fig, items = draw_map(config, lang, layout, frame, tiles, track, outline)
        trip.report_overlaps(fig, items, lang)
        path = config.output(config.paths.images, "route-map", lang, ".png")
        outputs.append((path, trip.save_png(fig, path)))
    for lang in languages:
        fig = draw_profile(config, lang)
        if fig is None:
            trip.log(f"[{lang}] elevation profile skipped: no night's place has an elevation")
            continue
        path = config.output(config.paths.images, "elevation-profile", lang, ".png")
        outputs.append((path, trip.save_png(fig, path)))
    outputs.append((config.paths.gpx, write_gpx(config, track)))
    for path, digest in outputs:
        trip.print_output(path, digest)
    return trip.EXIT_OK


def main(argv: list[str] | None = None) -> int:
    trip.configure_console()
    parser = trip.argument_parser(__doc__.split("\n")[0], USAGE)
    parser.add_argument("config", help="trip configuration (YAML); paths are relative to it")
    parser.add_argument("--lang", action="append", metavar="LANG",
                        help="build only this language (repeatable; default: every language)")
    parser.add_argument("--offline", action="store_true",
                        help="use cached downloads only; fail with exit code 3 when one is missing")
    args = parser.parse_args(argv)

    def body(config: trip.Trip, http: trip.Http) -> int:
        languages = args.lang or config.languages
        unknown = [lang for lang in languages if lang not in config.languages]
        if unknown:
            raise trip.ConfigError([f"--lang: {lang!r} is not in languages "
                                    f"({', '.join(config.languages)})" for lang in unknown])
        return build(config, http, languages)

    return trip.run(args.config, args.offline, body)


if __name__ == "__main__":
    raise SystemExit(main())
