---
name: travel-handbook
compatibility: >-
  Requires uv, which fetches Python 3.11 or later and each script's
  dependencies from its inline header (matplotlib, Pillow, requests, astral,
  ruamel.yaml, tzdata). Needs network access to OpenTopoMap, Nominatim, the
  Open-Meteo archive and elevation APIs, and Wikimedia Commons.
description: >-
  Builds the maps, charts, photos, and checks of a two-language trip handbook
  from one YAML trip configuration. Use this skill when a guide written before
  a journey needs a route map, climate or daylight charts, a trip calendar, or
  licensed photos, or when its language versions drift apart, even if nobody
  says handbook.
  USE FOR: route maps with locator inset and elevation profile, GPX for hiking
  apps, per-night temperatures at altitude, daylight and twilight, trip
  calendars, Plan B regions maps, Wikimedia Commons photos with licences and
  credits, overlapping map labels, Open-Meteo or Commons rate limits, name.md
  and name.<lang>.md twins, heading anchors and reference links.
  DO NOT USE FOR: planning or changing the itinerary (use travel-planning),
  signed-in forum reading (use authenticated-web-extraction), a diary built
  after the trip from the travellers' own photos, Word or PDF export (use
  pandoc-docx-export).
---

# Travel Handbook

Builds a trip handbook's maps, charts, photos, and two-language checks before
the journey, from public sources and one trip configuration file. The scripts
encode what took the most reruns by hand: map geometry, rate limits, licences,
and keeping two language versions in step. Planning the trip itself belongs to
`travel-planning`; a diary from the travellers' own photos after the trip is out
of scope.

## Start

1. Copy [`assets/trip.example.yaml`](assets/trip.example.yaml) next to the
   handbook as `trip.yaml` and fill it in. Read
   [`references/trip-config.md`](references/trip-config.md) when you write or
   change the configuration. Every download carries `user_agent`: give it the
   project's URL, never an invented address, and a personal e-mail address only
   with its owner's consent.
2. Take coordinates from the GPS track first, then Wikidata P625, OSM
   Nominatim, and Wikivoyage, and write where each came from into the place's
   `source`. Check published altitudes against the Open-Meteo elevation API
   (Copernicus GLO-90): differences of 25 to 90 m are normal, and it fills gaps.
3. Run every script through `uv run`; it installs the dependencies from the
   script's header. `--help` lists the arguments and exit codes.

## Build

`<skill>` below is the folder of this file (installed:
`~/.copilot/skills/travel-handbook`). Every script prints one
`<sha256>  <path>` line per output and, on stderr, a summary that counts HTTP
429 answers. Exit codes: 0 done, 1 a check failed, 2 bad arguments or
configuration, 3 network failure after bounded retries (rerun later; the cache
keeps the progress). `--offline` rebuilds from the cache alone.

1. **Map.** `uv run <skill>/scripts/build_map.py trip.yaml` draws the route map
   with its locator inset, the elevation profile, and the GPX, in every
   language. Move a label with the place's `label` offset until stderr reports
   no overlap in any language.
2. **Charts.** `uv run <skill>/scripts/build_charts.py trip.yaml` draws the
   per-night temperatures, daylight, trip calendar, and Plan B map; `--only`
   limits it to some of them. Paste each language's temperature table, written
   next to the chart, into the chapter and its twin; from then on `--check`
   must exit 0 on every build.
3. **Photos.** `uv run <skill>/scripts/fetch_photos.py trip.yaml --candidates`
   builds one numbered contact sheet per `photo_candidates` subject. Look at
   the sheets, put the chosen files under `photos`, then run it without
   `--candidates` to crop them and write the credits tables.
4. **Documents.** `uv run <skill>/scripts/check_docs.py --config trip.yaml`
   checks links, anchors, reference labels, and the twins; fix every line it
   prints.

## Gotchas

### Maps

- OpenTopoMap tiles need the attribution "Map data © OpenStreetMap
  contributors, SRTM · Map style © OpenTopoMap (CC-BY-SA)" on the map, a
  descriptive User-Agent, and a tile cache; the scripts do all three.
- CARTO raster tiles returned "API KEY REQUIRED" images. The locator inset
  draws the country outline from Nominatim instead.
- The longitude span must follow from the axes' aspect ratio at the zoom
  level, or the map gets blank strips.
- A Google My Maps export names its route segments with `(N)`; the unnumbered
  segment is segment 1.
- Translated labels are longer: read the overlap report for every language,
  not only the first.
- The Windows console code page cannot print Cyrillic and other non-Latin
  scripts. The scripts write UTF-8; in PowerShell, set
  `[Console]::OutputEncoding = [Text.Encoding]::UTF8` first, or names arrive
  garbled (`Br├╝cke`), and set `PYTHONIOENCODING=utf-8` for any other
  Python you run.
- Quantized to 256 colours, a map weighs about 1 MB and a chart 20 to 50 KB.
  Compare the printed hashes of two builds to prove a rebuild is deterministic.
  For OsmAnd and Organic Maps, a GPX with every fourth track point is enough.

### Climate

- The Open-Meteo archive corrects to a place's altitude with `elevation=<m>`.
  Ten-year daily requests hit HTTP 429 after about six places, so the script
  asks for one date window per year and caches every answer.
- Open-Meteo's default archive blend ran about 5 °C warmer at night than a
  valley station's normals, and ERA5 alone came within about 1 °C, so the
  script asks for `models=era5`. Still compare with a nearby station, for
  example from a Wikipedia `{{Weather box}}` read through `action=raw` that
  cites the national weather service, and state any bias in the chapter.
- The chapter's numbers drift from the chart when either changes by hand:
  run the temperature check on every build.
- Daylight assumes a flat horizon; say that deep valleys see the sun later and
  lose it earlier.

### Photos

- Accept only CC0, public domain, CC BY, and CC BY-SA. Commons returns Artist
  as HTML and CC0 licence links as http; the script strips the HTML, escapes
  what is left, and rewrites the links to https.
- Category queries with full metadata at `gcmlimit=200` hit HTTP 429; the
  script uses 50, backs off 20 to 30 s, and pauses between downloads. Do not
  start a second search loop beside it.
- Searching `incategory:"Quality_images"` returned nothing; the script ranks
  candidates by their Quality image and Featured picture categories instead.
- Bound the search: one numbered contact sheet per subject, then choose. An
  open-ended photo hunt once took 38 minutes and needed steering twice.
- Check each chosen photo against its file description and the route: one
  showed a village off the planned route variant, and another lacked the
  mountain its caption named.
- The crops (3:2 at 960×640 and an 8:3 banner at 1600×600) carry no metadata,
  neither EXIF nor XMP, so no GPS position. The credits table names author,
  licence link, and file page, and says that a crop keeps the original licence
  (ShareAlike where it applies).

### Two languages

- Twins are `name.md` and `name.<lang>.md`. Their headings, table rows, list
  items, callouts, link definitions, images, and link targets must match; the
  document check compares them.
- Give each chapter only the reference definitions it uses. markdownlint does
  not catch an undefined label; the document check does.
- Number formats differ by language. Russian, for example, uses a decimal
  comma, writes four-digit numbers without a separator, and groups five or more
  digits with a space. Quote originals verbatim, and never put a translation in
  quotation marks.
- A general-purpose subagent translates a chapter well. Check its result
  number by number, then headings, table rows, and link definitions.
- Keep emoji out of headings that are link targets, and count an emoji as two
  characters toward MD013; the Markdown Instruction has the details.

## Verification

Before reporting, show:

- The document check exits 0 for every chapter pair.
- The temperature check exits 0 against the weather chapter.
- Two builds print the same hashes for every map and chart.
- Every photo has a credits row with author, licence link, and file page.
- The script's 429 count, and the gaps it left, in the report.
