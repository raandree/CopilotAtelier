"""Offline fixtures for the travel-handbook toolkit tests.

Every HTTP request goes to the synthetic web in synthetic.py; a test that tries
to open a real connection fails. Outputs go to pytest's tmp_path only.
"""
from __future__ import annotations

import shutil
import sys
import textwrap
from pathlib import Path

import pytest

from synthetic import FIXTURES, FakeClock, SyntheticWeb

REPO = Path(__file__).resolve().parents[2]
SKILL = REPO / "skills" / "travel-handbook"
SCRIPTS = SKILL / "scripts"
EXAMPLE = SKILL / "assets" / "trip.example.yaml"

if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


@pytest.fixture(autouse=True)
def no_real_network(monkeypatch):
    """Fail any attempt to open a real connection."""
    import socket

    def refuse(*args, **kwargs):
        raise AssertionError("tests must not reach the network")

    monkeypatch.setattr(socket.socket, "connect", refuse)
    import requests

    monkeypatch.setattr(requests.sessions.Session, "request", refuse)


@pytest.fixture
def fake_clock(monkeypatch):
    import trip

    clock = FakeClock()
    monkeypatch.setattr(trip, "sleep", clock.sleep)
    monkeypatch.setattr(trip, "utcnow", clock.now)
    return clock


@pytest.fixture
def network(monkeypatch, fake_clock):
    """Route every request of the scripts to the synthetic web."""
    import trip

    web = SyntheticWeb()
    monkeypatch.setattr(trip, "new_session", lambda: web.session)
    return web


@pytest.fixture
def write_config(tmp_path):
    def write(text: str, name: str = "trip.yaml") -> Path:
        path = tmp_path / name
        path.write_text(textwrap.dedent(text), encoding="utf-8")
        return path

    return write


@pytest.fixture
def example_path() -> Path:
    return EXAMPLE


@pytest.fixture
def example_copy(tmp_path) -> Path:
    """The shipped example configuration, copied with its synthetic track into tmp_path."""
    target = tmp_path / "handbook"
    (target / "tracks").mkdir(parents=True)
    shutil.copyfile(EXAMPLE, target / "trip.yaml")
    shutil.copyfile(FIXTURES / "example-route.gpx", target / "tracks" / "example-route.gpx")
    return target / "trip.yaml"
