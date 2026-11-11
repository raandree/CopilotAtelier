# Trip configuration

Every script of the travel-handbook toolkit reads one YAML file that
describes the trip. This reference lists each key with its type, default, and
checks. A complete synthetic example is
[`assets/trip.example.yaml`](../assets/trip.example.yaml).

## Contents

- [Loading rules](#loading-rules)
- [Top-level keys](#top-level-keys)
- [Languages and output names](#languages-and-output-names)
- [Paths](#paths)
- [Places](#places)
- [Nights and high points](#nights-and-high-points)
- [Route](#route)
- [Map](#map)
- [Calendar](#calendar)
- [Plan B](#plan-b)
- [Climate](#climate)
- [Photos](#photos)
- [Labels](#labels)
- [Numbers](#numbers)
- [Problems and exit codes](#problems-and-exit-codes)

## Loading rules

- The file is read as YAML 1.2 with ruamel.yaml's pure safe loader. An
  unquoted `NO`, `yes`, `on`, or `off` stays a string; only `true` and
  `false` are booleans. A duplicate key is an error.
- Validation is strict. An unknown key, a wrong type, or a missing required
  key fails with one message per problem that names its path, for example
  `places.alpha.lat: expected a number, got 'NO'`. Every problem is reported
  in the same run.
- Dates are YAML dates (`2027-07-01`) or ISO strings (`"2027-07-01"`). A
  date with a time of day is an error.
- Relative paths are resolved against the folder that holds the
  configuration file, not against the working directory.
- Text that differs by language is either one string, used for every
  language, or a mapping with one entry per configured language, such as
  `name: {en: Alpha Village, de: Alphadorf}`. A missing entry fails with
  `places.alpha.name.de: missing translation`.
- Keys of places, photo names, and candidate subjects use only letters,
  digits, `_`, and `-`.

## Top-level keys

| Key | Type | Required | Meaning |
|---|---|---|---|
| `languages` | list of codes | yes | Handbook languages; the first is the primary one |
| `user_agent` | text | yes | Sent with every request; names the tool and a contact |
| `timezone` | IANA name | yes | Local time of the trip, for example `Europe/Zurich` |
| `places` | mapping | yes | Every place the other sections refer to |
| `nights` | list | yes | Where each night is spent, in date order |
| `title` | text per language | no | Name in the GPX file's metadata |
| `country` | text | no | Outline for the locator inset and the Plan B map |
| `paths` | mapping | no | Output and cache folders |
| `high_points` | list | no | Highest point reached on a day |
| `route` | mapping | no | GPS track and drawn connections |
| `map` | mapping | no | Replaces derived settings of the route map |
| `calendar` | mapping | no | Phases, decision points, validity windows |
| `plan_b` | mapping | no | Alternative regions and their status |
| `climate` | mapping | no | Temperature window, years, places, chapter |
| `photos` | list | no | Wikimedia Commons photos to crop and credit |
| `photo_candidates` | list | no | Subjects for contact sheets |
| `labels` | mapping | no | Chart text per language |
| `numbers` | mapping | no | Number format per language |

`user_agent` must contain an e-mail address or a URL: the OpenTopoMap tile
servers, Nominatim, Open-Meteo, and Wikimedia Commons refuse anonymous clients,
and every request carries it. Prefer the project's URL, for example
`my-trip-handbook/1.0 (https://github.com/<owner>/<repository>)`. Put a
personal e-mail address there only with its owner's consent, and never invent
one. A `user_agent` that contains `@` draws a warning on stderr.

`country` is sent to Nominatim's `country=` search, so any name or code it
knows works. YAML 1.2 keeps an unquoted `NO` a string. Without `country` the
route map has no locator inset and the Plan B map has no outline.

## Languages and output names

`languages: [en, de]` makes English the primary language. Outputs follow the
naming of twin documents (`name.md` and `name.<lang>.md`): the primary
language gets `name.png`, every other language `name.<lang>.png`.

| Script | Outputs per language | Folder |
|---|---|---|
| `build_map.py` | `route-map.png`, `elevation-profile.png` | `paths.images` |
| `build_map.py` | `route.gpx`, one file for all languages | `paths.gpx` |
| `build_charts.py` | `weather-temperatures.png` and `weather-temperatures.md` | `paths.images` |
| `build_charts.py` | `daylight.png`, `trip-calendar.png`, `plan-b-regions.png` | `paths.images` |
| `fetch_photos.py` | `<name>.jpg` for all languages, `credits.md` per language | `paths.photos` |
| `fetch_photos.py --candidates` | `<subject>.jpg` contact sheets | `<cache>/candidates` |

Each script prints one `<sha256>  <path>` line per output on stdout, so two
runs can be compared to prove that a rebuild is identical.

## Paths

| Key | Default | Holds |
|---|---|---|
| `images` | `docs/images` | Maps, charts, and temperature tables |
| `gpx` | `docs/maps/route.gpx` | The GPX export |
| `photos` | `docs/images/photos` | Photo crops and credits tables |
| `docs` | `[README.md, docs]` | Files and folders that `check_docs.py` checks |
| `cache` | `.cache/travel-handbook` | Every download; delete it to refresh |

## Places

```yaml
places:
  alpha:
    name: {en: Alpha Village, de: Alphadorf}
    lat: 45.905
    lon: 7.080
    elevation: 1420
    source: Synthetic example
    label: {dx: -12, dy: -20, align: right}
```

| Key | Type | Required | Meaning |
|---|---|---|---|
| `name` | text per language | yes | Name on maps, charts, and tables |
| `lat`, `lon` | number | yes | Position in degrees, WGS 84 |
| `source` | text | yes | Where the coordinates come from |
| `elevation` | number | no | Metres; see [Climate](#climate) when missing |
| `label` | mapping | no | Map label offset: `dx`, `dy` in pixels, `align` |

The label offset defaults to 16 pixels right and 10 pixels up, aligned
`left`; `+dy` is up. `build_map.py` prints every overlap of labels, markers,
the legend, the attribution, and the locator inset for each language, because
longer translations overlap more. Move a label with `label` until the run
reports no overlaps.

## Nights and high points

```yaml
nights:
  - {date: 2027-07-01, place: gateway}
  - {date: 2027-07-02, place: alpha}
high_points:
  - {date: 2027-07-04, place: bravo_pass}
```

`nights` lists one entry per night in strictly increasing date order; each
`place` must be a key of `places`. The route map numbers the nights from 1,
and a place used on several nights shows all its numbers, such as `4/5`.
`high_points` marks the highest point of a day on the map and on the
elevation profile.

## Route

| Key | Type | Meaning |
|---|---|---|
| `gpx` | path | A GPX file; its track segments are numbered 1, 2, ... in file order |
| `my_maps` | text | A Google My Maps id, downloaded as KML |
| `segments` | list of numbers | The segments to draw; default: every segment |
| `credit` | text per language | Appended to the map attribution |
| `variants` | list of place lists | Planned connections off the track, dashed |
| `day_hikes` | list of place lists | Out-and-back hikes, dotted |
| `transfers` | list of place lists | Road or rail transfers, grey; also on the locator |

Give exactly one of `gpx` and `my_maps`. A My Maps map is read from
`https://www.google.com/maps/d/kml?mid=<id>&forcekml=1`; its segment names
carry `(N)`, and the segment without a number is segment 1. A missing segment
number fails with `route.segments: segment 9 not found`. An answer that is not
KML, such as the sign-in page of a map that is not shared publicly, and a
malformed coordinate in the KML or GPX file fail with code 2; such an answer is
never cached, so the next run after the fix downloads the map again.

The GPX export for OsmAnd or Organic Maps keeps every fourth track point and
writes one waypoint per night's place and per high point, described in every
language.

## Map

Every key is optional; the defaults come from the places.

| Key | Type | Default |
|---|---|---|
| `zoom` | 1 to 17 | The level at which the latitude range fills the 900-pixel map |
| `lat` | `[lat_min, lat_max]` | Covers the places, high points, and track |
| `lon_center` | number | The middle of the covered points |
| `margin` | 0 to 0.45 | `0.12` of the map kept free around the points |
| `exclude` | list of places | None; excluded places appear only on the locator |
| `locator.extent` | `[lon_min, lat_min, lon_max, lat_max]` | The country outline |
| `locator.labels` | list of `{text, lat, lon}` | None |

The longitude span is always derived from the map's aspect ratio at the zoom
level; a span chosen any other way leaves blank strips. The tiles come from
OpenTopoMap with the attribution "Map data © OpenStreetMap contributors,
SRTM · Map style © OpenTopoMap (CC-BY-SA)" on the map, and every tile is
cached. The locator inset takes the corner that covers the fewest points.

## Calendar

```yaml
calendar:
  start: 2027-06-29
  end: 2027-07-09
  phases:
    - {start: 2027-07-01, end: 2027-07-01, label: {en: Arrival, de: Anreise}}
  markers:
    - {date: 2027-07-03, label: {en: "Bravo Hut: cross or wait", de: "Bravohütte: queren oder warten"}}
  windows:
    - start: 2027-06-15
      end: 2027-09-15
      label: {en: Cable car running, de: Seilbahn in Betrieb}
      note: {en: "15 Jun – 15 Sep", de: "15. Juni – 15. Sept."}
```

| Key | Meaning |
|---|---|
| `start`, `end` | Calendar range; default: one day before the first and after the last night, phase, or marker |
| `phases` | Bars of the plan row: `start`, `end`, `label`, optional `color` (`"#rrggbb"`) |
| `markers` | Numbered decision points on the plan row: `date`, `label`; the labels are listed under the chart |
| `windows` | One row each, clipped to the calendar: `start`, `end`, `label`, optional `note` and `color` |

## Plan B

```yaml
plan_b:
  regions:
    - name: {en: Foxtrot Valley, de: Foxtrottal}
      lat: 46.05
      lon: 7.30
      status: open
      note: {en: trails open, de: Wege offen}
```

`status` is `open`, `limited`, or `closed`. `note`, `dx`, and `dy` (label
offset in points, default 14 and 14) are optional. `extent` defaults to the
country outline. The map also draws the route through every night's place.

## Climate

```yaml
climate:
  window: ["07-01", "07-07"]
  years: 10
  chapter: docs/weather.md
```

| Key | Type | Required | Meaning |
|---|---|---|---|
| `window` | two `MM-DD` values | yes | Inclusive; it may wrap past 31 December |
| `years` | 1 to 40 | yes | Number of past windows to average |
| `last_year` | year | no | Default: the latest year whose window ended a week ago |
| `places` | list of places | no | Default: every night's place |
| `chapter` | path | no | Chapter whose temperature table is checked on every run |

`build_charts.py` requests the ERA5 daily minimum and maximum from the
Open-Meteo archive once per year and place, for the window only, with
`elevation=<m>` so the values match each place's height, and with
`models=era5`: the archive's default blend of models ran about 5 °C warmer at
night than a valley station's normals, ERA5 alone within about 1 °C. Each
answer is cached; ten-year daily requests are refused with HTTP 429 after a
handful of places. ERA5 reaches the archive about five days late: a year whose
window lacks a day stops the run with code 3, names the place and the dates,
and stays out of the cache. A place without an elevation gets one from the
Open-Meteo elevation API (Copernicus GLO-90); the run says so on stderr, and
the table marks the value `(DEM)`.

The script writes `weather-temperatures.md` and its twins next to the chart:
one row per night with the mean night and day temperature, the cold night
that one night in ten is colder than, and the lowest night. The chapter named
in `chapter`, and its twins such as `docs/weather.de.md`, must contain
exactly that table. A difference exits with code 1 and names the row, for
example `docs/weather.de.md: row '2. Juli | Alphadorf': Nacht, Mittel (°C)
is '3,4' in the chapter, computed '3,5'`. `--check` runs only this
comparison.

## Photos

```yaml
photos:
  - name: banner
    file: "File:Example valley panorama (synthetic).jpg"
    focus: 0.45
    banner: true
    caption: {en: The valley above Alpha Village, de: Das Tal oberhalb von Alphadorf}
  - place: charlie_lake
    file: "File:Charlie Lake at dawn (synthetic).jpg"
    focus: [0.5, 0.6]
    caption: {en: Charlie Lake at dawn, de: Der Charliesee im Morgenlicht}
photo_candidates:
  - {subject: charlie-lake, category: "Category:Charlie Lake (synthetic)", limit: 12}
  - {subject: echo-view, search: Echo viewpoint panorama}
```

| Key | Meaning |
|---|---|
| `file` | Commons file title, starting with `File:` |
| `caption` | Text per language for the credits table |
| `name` | Output file stem; default: the `place` key |
| `place` | The place the photo shows; optional |
| `focus` | Vertical focus from 0 (top) to 1 (bottom), or `[x, y]`; default `0.5` |
| `banner` | `true` for an 8:3 banner of 1600 by 600 pixels; default a 3:2 crop of 960 by 640 |

Only CC0, public domain, CC BY, and CC BY-SA files are accepted; any other
license exits with code 1 and names the photo. Photos come only as renditions
from `https://upload.wikimedia.org`, never as the full original; a photo
without one is refused the same way. Crops are saved from their pixels alone,
without EXIF, XMP, or any other metadata, which removes GPS positions. The
credits table per language names the author and links the license and the
file page. Commons text is escaped, so it cannot add HTML or links; the license
is a link only when it is https on Creative Commons, Wikimedia, or Wikipedia
(Creative Commons links use https), and the file page only when it is https on
`commons.wikimedia.org`; otherwise each stays plain text. The table states that
each crop keeps the license of its original.

`photo_candidates` entries give a `subject` and exactly one of `category`
(a `Category:` title) and `search` (a full-text search in the File
namespace); `limit` is 1 to 50 and defaults to 24. `fetch_photos.py
--candidates` builds one numbered contact sheet per subject, featured and
quality images first. A file whose thumbnail fails to download or decode is
left out of the sheet and named on stderr, and the run goes on.

## Labels

English chart text is built in. Every other language must supply each label
of the features the file uses, or validation fails with, for example,
`labels.de.map_title: missing label`. An entry under `labels.en` replaces the
built-in English text; an unknown key fails with `unknown label`.

| Feature | Needed when | Keys |
|---|---|---|
| Common | always | `months` (12 names), `date_format` (`{day}`, `{month}`), `unit_m`, `unit_c` |
| Map and profile | always | `map_title`, `map_track`, `map_variant`, `map_day_hike`, `map_transfer`, `map_stop`, `map_high`, `map_area`, `map_panel`, `profile_title`, `profile_axis`, `profile_sleep`, `profile_note` |
| Daylight | always | `daylight_title`, `daylight_note` (`{timezone}`), `daylight_axis`, `daylight_day`, `daylight_twilight`, `daylight_night`, `daylight_length` (`{hours}`, `{minutes}`) |
| Climate | `climate` is set | `temperature_title`, `temperature_note` (`{window}`, `{first_year}`, `{last_year}`), `temperature_axis`, `temperature_below`, `temperature_above`, `temperature_cold`, `table_date`, `table_place`, `table_elevation`, `table_night`, `table_day`, `table_cold`, `table_lowest`, `table_dem_note` |
| Calendar | `calendar` is set | `calendar_title`, `calendar_plan`, `calendar_marker`, `calendar_markers_note` (`{items}`) |
| Plan B | `plan_b` is set | `plan_b_title`, `plan_b_note`, `plan_b_route`, `status_open`, `status_limited`, `status_closed` |
| Photos | `photos` is set | `credits_title`, `credits_note`, `credits_photo`, `credits_author`, `credits_license`, `credits_file` |

Placeholders in braces are filled in by the scripts; a placeholder outside
the listed ones fails validation.

## Numbers

| Language | Decimal | Groups | Example |
|---|---|---|---|
| `en` | point | comma from four digits | `1,234.5` |
| `de` | comma | point from four digits | `1.234,5` |
| `ru` | comma | no-break space from five digits | `1234,5` and `12 345` |

Negative numbers use the minus sign `−`, and values are rounded half up. Any
part can be replaced per language:

```yaml
numbers:
  de: {group_min_digits: 5}
  fr: {decimal: ",", group: "\u202f", group_min_digits: 5}
```

The keys are `decimal`, `group`, `group_min_digits`, and `minus`. A language
without a built-in format needs at least `decimal` and `group`, or
validation fails with `numbers.fr: missing number format`.

## Problems and exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | A check failed: chapter table, document check, or a refused photo license |
| 2 | Bad arguments, an invalid configuration, or an unusable path |
| 3 | A download failed after bounded retries, or `--offline` found no cached copy |

Every script that downloads prints, at the end of each run, how many
requests went to the network, how many came from the cache, and how many
answers were HTTP 429. Retries honour `Retry-After`; a request for a wait
longer than five minutes stops the run with code 3, and the cache keeps all
progress for the next run. An answer longer than 50 MB, or an image that is
not PNG, JPEG, or WebP or is large enough to be a decompression bomb, counts
as a failed download and is never cached.
