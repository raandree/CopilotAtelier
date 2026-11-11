"""Number formatting per language: built-in en, de, ru formats and configured replacements."""
from __future__ import annotations

import pytest

import trip
from synthetic import MINIMAL, labels_json

NBSP = "\u00a0"
MINUS = "\u2212"


@pytest.mark.parametrize("language, value, decimals, expected", [
    ("en", 999, 0, "999"),
    ("en", 1234.5, 1, "1,234.5"),
    ("en", 12345, 0, "12,345"),
    ("en", -3.25, 1, f"{MINUS}3.3"),
    ("de", 1234, 0, "1.234"),
    ("de", 1234.5, 1, "1.234,5"),
    ("de", -0.5, 1, f"{MINUS}0,5"),
    ("ru", 1234, 0, "1234"),
    ("ru", 2870.5, 1, "2870,5"),
    ("ru", 12345, 0, f"12{NBSP}345"),
    ("ru", 1234567.25, 2, f"1{NBSP}234{NBSP}567,25"),
    ("ru", -12345.6, 1, f"{MINUS}12{NBSP}345,6"),
])
def test_builtin_number_formats(language, value, decimals, expected):
    assert trip.format_number(value, decimals, trip.BUILTIN_NUMBER_FORMATS[language]) == expected


def test_negative_zero_prints_as_zero():
    assert trip.format_number(-0.04, 1, trip.BUILTIN_NUMBER_FORMATS["en"]) == "0.0"


def test_rounding_is_half_up():
    english = trip.BUILTIN_NUMBER_FORMATS["en"]

    assert trip.format_number(2.25, 1, english) == "2.3"
    assert trip.format_number(2.35, 1, english) == "2.4"
    assert trip.format_number(0.5, 0, english) == "1"


def test_configuration_replaces_part_of_a_builtin_format(write_config):
    text = MINIMAL.replace("languages: [en]", "languages: [en, de]")
    text = text.replace("name: Alpha Village", "name: {en: Alpha Village, de: Alphadorf}")
    text += f"labels:\n  de: {labels_json(trip.DEFAULT_LABELS['en'])}\n"
    text += "numbers:\n  de:\n    group: \"'\"\n"
    config = trip.load_config(write_config(text))

    assert config.number("de", 12345.5, 1) == "12'345,5"
    assert config.number("en", 12345.5, 1) == "12,345.5"


def test_language_without_builtin_format_needs_one(write_config):
    text = MINIMAL.replace("languages: [en]", "languages: [en, fr]")
    text = text.replace("name: Alpha Village", "name: {en: Alpha Village, fr: Village Alpha}")
    text += f"labels:\n  fr: {labels_json(trip.DEFAULT_LABELS['en'])}\n"

    with pytest.raises(trip.ConfigError) as caught:
        trip.load_config(write_config(text))

    assert any(problem.startswith("numbers.fr: missing number format")
               for problem in caught.value.problems)


def test_elevations_are_formatted_per_language(example_path):
    config = trip.load_config(example_path)

    assert config.elevation_text("en", 2310) == "2,310 m"
    assert config.elevation_text("de", 2310) == "2.310 m"
