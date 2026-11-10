"""Loading the trip configuration: YAML 1.2, strict validation, one message per problem."""
from __future__ import annotations

from datetime import date

import pytest

import trip
from synthetic import MINIMAL, labels_json


def problems_of(path):
    with pytest.raises(trip.ConfigError) as caught:
        trip.load_config(path)
    assert caught.value.exit_code == 2
    return caught.value.problems


def two_languages(text: str, drop=(), extra=None) -> str:
    """Turn the minimal configuration into an English and German one with full labels."""
    text = text.replace("languages: [en]", "languages: [en, de]")
    text = text.replace("name: Alpha Village", "name: {en: Alpha Village, de: Alphadorf}")
    german = labels_json(trip.DEFAULT_LABELS["en"], drop=drop, extra=extra)
    return text + f"labels:\n  de: {german}\n"


def test_example_configuration_loads(example_path):
    config = trip.load_config(example_path)

    assert config.languages == ["en", "de"]
    assert config.primary == "en"
    assert config.timezone_name == "Europe/Zurich"
    assert [night.date for night in config.nights][:2] == [date(2027, 7, 1), date(2027, 7, 2)]
    assert config.name("alpha", "de") == "Alphadorf"
    assert config.paths.images == example_path.parent / "docs" / "images"


def test_minimal_configuration_loads(write_config):
    config = trip.load_config(write_config(MINIMAL))

    assert config.languages == ["en"]
    assert config.places["alpha"].elevation == 1450
    assert config.climate is None and config.calendar is None and config.plan_b is None


def test_unquoted_no_and_off_stay_strings(write_config):
    text = MINIMAL.replace("name: Alpha Village", "name: off") + "country: NO\n"
    config = trip.load_config(write_config(text))

    assert config.country == "NO"
    assert config.name("alpha", "en") == "off"


def test_wrong_type_is_reported_with_its_path(write_config):
    path = write_config(MINIMAL.replace("lat: 45.9", "lat: NO"))

    assert "places.alpha.lat: expected a number, got 'NO'" in problems_of(path)


def test_boolean_is_not_a_number(write_config):
    path = write_config(MINIMAL.replace("elevation: 1450", "elevation: true"))

    assert any(problem.startswith("places.alpha.elevation: expected a number")
               for problem in problems_of(path))


def test_unknown_key_is_rejected(write_config):
    path = write_config(MINIMAL.replace("    source:", "    colour: red\n    source:"))

    assert any(problem.startswith("places.alpha.colour: unknown key")
               for problem in problems_of(path))


def test_missing_required_key_is_reported(write_config):
    text = MINIMAL.replace('user_agent: "travel-handbook-tests/1.0 (tests@example.org)"\n', "")

    assert "user_agent: missing required key" in problems_of(write_config(text))


def test_missing_label_names_the_key(write_config):
    path = write_config(two_languages(MINIMAL, drop=("map_title",)))

    assert any(problem.startswith("labels.de.map_title: missing label")
               for problem in problems_of(path))


def test_complete_labels_for_a_second_language_load(write_config):
    config = trip.load_config(write_config(two_languages(MINIMAL)))

    assert config.languages == ["en", "de"]
    assert config.name("alpha", "de") == "Alphadorf"


def test_unknown_label_is_rejected(write_config):
    path = write_config(two_languages(MINIMAL, extra={"map_titel": "Karte"}))

    assert any(problem.startswith("labels.de.map_titel: unknown label")
               for problem in problems_of(path))


def test_label_with_an_unknown_placeholder_is_rejected(write_config):
    path = write_config(two_languages(MINIMAL, extra={"daylight_note": "Zeit {zone}"}))

    assert any(problem.startswith("labels.de.daylight_note: unknown placeholder {zone}")
               for problem in problems_of(path))


def test_missing_translation_of_a_place_name(write_config):
    text = two_languages(MINIMAL).replace("name: {en: Alpha Village, de: Alphadorf}",
                                          "name: {en: Alpha Village}")

    assert "places.alpha.name.de: missing translation" in problems_of(write_config(text))


def test_every_problem_is_reported_at_once(write_config):
    text = MINIMAL.replace("lat: 45.9", "lat: NO").replace("timezone: Europe/Zurich",
                                                           "timezone: Mars/Olympus")
    problems = problems_of(write_config(text))

    assert "places.alpha.lat: expected a number, got 'NO'" in problems
    assert "timezone: unknown IANA time zone 'Mars/Olympus'" in problems


def test_dates_accept_yaml_dates_and_iso_strings(write_config):
    text = MINIMAL + '  - {date: "2027-07-02", place: alpha}\n'
    config = trip.load_config(write_config(text))

    assert [night.date for night in config.nights] == [date(2027, 7, 1), date(2027, 7, 2)]


def test_invalid_date_is_reported(write_config):
    path = write_config(MINIMAL.replace("date: 2027-07-01", 'date: "1 July"'))

    assert "nights[0].date: expected a date (YYYY-MM-DD), got '1 July'" in problems_of(path)


def test_nights_must_be_in_date_order(write_config):
    path = write_config(MINIMAL + "  - {date: 2027-06-30, place: alpha}\n")

    assert any(problem.startswith("nights[1].date: must come after")
               for problem in problems_of(path))


def test_unknown_place_in_nights_is_reported(write_config):
    path = write_config(MINIMAL.replace("place: alpha}", "place: zulu}"))

    assert any(problem.startswith("nights[0].place: unknown place 'zulu'")
               for problem in problems_of(path))


def test_climate_places_must_include_a_night(write_config):
    text = MINIMAL.replace("nights:", """\
  bravo:
    name: Bravo Hut
    lat: 45.93
    lon: 7.12
    source: Synthetic test data
nights:""") + "climate:\n  window: [\"07-01\", \"07-07\"]\n  years: 3\n  places: [bravo]\n"

    assert "climate.places: no night is spent at any of these places" in problems_of(
        write_config(text))


def test_user_agent_needs_a_contact(write_config):
    text = MINIMAL.replace('"travel-handbook-tests/1.0 (tests@example.org)"', "python-requests")

    assert any(problem.startswith("user_agent: ") for problem in problems_of(write_config(text)))


def test_user_agent_problem_suggests_a_url_rather_than_an_address(write_config):
    text = MINIMAL.replace('"travel-handbook-tests/1.0 (tests@example.org)"', "python-requests")

    problem = next(problem for problem in problems_of(write_config(text))
                   if problem.startswith("user_agent: "))

    assert "https://" in problem
    assert "@" not in problem


def test_user_agent_with_an_address_draws_a_warning(write_config, capsys):
    trip.load_config(write_config(MINIMAL))  # its user_agent carries tests@example.org

    err = capsys.readouterr().err
    assert "user_agent" in err and "e-mail address" in err


def test_user_agent_with_a_url_draws_no_warning(write_config, capsys):
    trip.load_config(write_config(MINIMAL.replace("tests@example.org",
                                                  "https://example.org/handbook")))

    assert capsys.readouterr().err == ""


@pytest.mark.parametrize("text, problem", [
    pytest.param(MINIMAL.replace("  alpha:\n", '  "alpha\\n":\n'),
                 "a place key may use only", id="place key"),
    pytest.param(MINIMAL + 'route:\n  my_maps: "synthetic-id\\n"\n',
                 "route.my_maps: expected the map id", id="my_maps id"),
    pytest.param(MINIMAL + 'photos:\n  - {name: "lake\\n", file: "File:Lake.jpg", caption: Lake}\n',
                 "photos[0].name: expected a file stem", id="photo name"),
    pytest.param(MINIMAL + 'photo_candidates:\n  - {subject: "lake\\n", search: lake}\n',
                 "photo_candidates[0].subject: expected a name", id="candidate subject"),
    pytest.param(MINIMAL.replace("languages: [en]", 'languages: ["en\\n"]'),
                 "languages[0]: expected a language code", id="language"),
    pytest.param(MINIMAL + 'calendar:\n  phases:\n    - {start: 2027-07-01, end: 2027-07-01, '
                           'label: Stay, color: "#2e86c1\\n"}\n',
                 "calendar.phases[0].color: expected a colour", id="colour"),
    pytest.param(MINIMAL + 'climate:\n  window: ["07-01\\n", "07-07"]\n  years: 3\n',
                 "climate.window: expected two month-day values", id="month-day"),
])
def test_a_trailing_line_break_makes_a_value_invalid(write_config, text, problem):
    problems = problems_of(write_config(text))

    assert any(problem in found for found in problems), problems


def test_yaml_syntax_error_is_a_configuration_error(write_config):
    problems = problems_of(write_config("languages: [en\nuser_agent: x\n"))

    assert len(problems) == 1 and "line" in problems[0]


def test_duplicate_key_is_a_configuration_error(write_config):
    problems = problems_of(write_config(MINIMAL + "timezone: UTC\n"))

    assert "duplicate" in problems[0].lower()


@pytest.mark.parametrize("script", ["build_map", "build_charts", "fetch_photos"])
def test_scripts_exit_2_on_an_invalid_configuration(script, write_config, capsys):
    module = __import__(script)
    path = write_config(MINIMAL.replace("lat: 45.9", "lat: NO"))

    assert module.main([str(path)]) == 2
    assert "places.alpha.lat: expected a number, got 'NO'" in capsys.readouterr().err


def test_check_docs_exits_2_on_an_invalid_configuration(write_config, capsys):
    import check_docs

    path = write_config(MINIMAL.replace("lat: 45.9", "lat: NO"))

    assert check_docs.main(["--config", str(path)]) == 2
    assert "places.alpha.lat" in capsys.readouterr().err


def test_output_names_follow_twin_documents(example_path):
    config = trip.load_config(example_path)

    assert config.output(config.paths.images, "route-map", "en", ".png").name == "route-map.png"
    assert config.output(config.paths.images, "route-map", "de", ".png").name == "route-map.de.png"


def test_paths_are_relative_to_the_configuration_file(write_config, tmp_path):
    config = trip.load_config(write_config(MINIMAL + "paths:\n  images: out/img\n"))

    assert config.paths.images == tmp_path / "out" / "img"
    assert config.paths.cache == tmp_path / ".cache" / "travel-handbook"
