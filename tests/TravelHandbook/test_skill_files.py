"""The shipped Skill files: dependency minimums in the script headers, neutral examples."""
from __future__ import annotations

import re
import tomllib
from pathlib import Path

import pytest
from packaging.requirements import Requirement
from packaging.version import Version

REPO = Path(__file__).resolve().parents[2]
SKILL = REPO / "skills" / "travel-handbook"
PESTER = REPO / "tests" / "TravelHandbook.Tests.ps1"
SCRIPTS = sorted((SKILL / "scripts").glob("*.py"))
# The reference expression of PEP 723 for an inline metadata block.
BLOCK = re.compile(r"(?m)^# /// (?P<type>[a-zA-Z0-9-]+)$\s(?P<content>(^#(| .*)$\s)+)^# ///$")
MINIMUMS = {
    "requests": Version("2.32.4"),  # CVE-2024-47081: a crafted URL leaks .netrc credentials
    "pillow": Version("10.3"),  # CVE-2024-28219: buffer overflow in _imagingcms.c
}


def dependencies(path: Path) -> list[Requirement]:
    """The requirements of a script's PEP 723 header; none without a header."""
    blocks = [match for match in BLOCK.finditer(path.read_text(encoding="utf-8"))
              if match["type"] == "script"]
    if not blocks:
        return []
    content = "".join(line[2:] if line.startswith("# ") else line[1:]
                      for line in blocks[0]["content"].splitlines(keepends=True))
    return [Requirement(text) for text in tomllib.loads(content).get("dependencies", [])]


def lowest(requirement: Requirement) -> Version | None:
    """The lowest version a requirement admits through its >= bounds."""
    return max((Version(spec.version) for spec in requirement.specifier if spec.operator == ">="),
               default=None)


@pytest.mark.parametrize("script", [path for path in SCRIPTS if dependencies(path)],
                         ids=lambda path: path.name)
def test_script_headers_require_patched_versions(script):
    for requirement in dependencies(script):
        minimum = MINIMUMS.get(requirement.name.lower())
        if minimum is not None:
            found = lowest(requirement)
            assert found is not None and found >= minimum, f"{script.name}: {requirement}"


def test_the_headers_name_every_pinned_package():
    names = {requirement.name.lower() for path in SCRIPTS for requirement in dependencies(path)}

    assert set(MINIMUMS) <= names


def test_the_pester_wrapper_installs_patched_versions():
    pins = [Requirement(text) for text in
            re.findall(r"'--with', '([^']+)'", PESTER.read_text(encoding="utf-8"))]
    found = {requirement.name.lower(): requirement for requirement in pins}

    for name, minimum in MINIMUMS.items():
        assert lowest(found[name]) is not None and lowest(found[name]) >= minimum, found[name]


def test_the_console_gotcha_garbles_a_neutral_word():
    text = (SKILL / "SKILL.md").read_text(encoding="utf-8")

    assert "(`Br├╝cke`)" in text
