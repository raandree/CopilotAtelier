"""The shared HTTP helper: User-Agent, disk cache, bounded retries, Retry-After, 429 count."""
from __future__ import annotations

import io

import pytest
from PIL import Image

import trip
from synthetic import FakeResponse, FakeSession, sequence

AGENT = "travel-handbook-tests/1.0 (tests@example.org)"
URL = "https://data.example.org/series"


class EndlessBody(FakeResponse):
    """An answer whose body never ends; counts the bytes handed out."""

    def __init__(self, status_code=200):
        super().__init__(status_code)
        self.served = 0

    def iter_content(self, chunk_size=1):
        while True:
            self.served += chunk_size
            yield b"x" * chunk_size


def image_bytes(size, image_format):
    buffer = io.BytesIO()
    Image.new("RGB", size, (90, 140, 60)).save(buffer, image_format)
    return buffer.getvalue()


def make_http(tmp_path, *responses, offline=False):
    session = FakeSession(sequence(*responses))
    return trip.Http(AGENT, tmp_path / "cache", session=session, offline=offline), session


def test_429_honours_retry_after_and_is_counted(tmp_path, fake_clock):
    http, session = make_http(tmp_path, FakeResponse(429, headers={"Retry-After": "7"}),
                              FakeResponse(200, b"ok"))

    assert http.get(URL) == b"ok"
    assert fake_clock.slept == [7]
    assert http.rate_limited == 1
    assert "1 HTTP 429" in http.summary()
    assert len(session.calls) == 2


def test_429_without_retry_after_backs_off_per_attempt(tmp_path, fake_clock):
    http, _ = make_http(tmp_path, FakeResponse(429), FakeResponse(429), FakeResponse(200, b"ok"))

    assert http.get(URL, backoff=20) == b"ok"
    assert fake_clock.slept == [20, 40]
    assert http.rate_limited == 2


def test_retry_after_as_an_http_date(tmp_path, fake_clock):
    later = "Tue, 01 Jan 2030 00:00:30 GMT"
    http, _ = make_http(tmp_path, FakeResponse(503, headers={"Retry-After": later}),
                        FakeResponse(200, b"ok"))

    assert http.get(URL) == b"ok"
    assert fake_clock.slept == [30]
    assert http.rate_limited == 0


def test_gives_up_after_bounded_attempts(tmp_path, fake_clock):
    responses = [FakeResponse(503) for _ in range(trip.MAX_ATTEMPTS)]
    http, session = make_http(tmp_path, *responses)

    with pytest.raises(trip.NetworkError) as caught:
        http.get(URL)

    assert caught.value.exit_code == 3
    assert len(session.calls) == trip.MAX_ATTEMPTS
    assert len(fake_clock.slept) == trip.MAX_ATTEMPTS - 1


def test_refuses_an_excessive_retry_after(tmp_path, fake_clock):
    http, session = make_http(tmp_path, FakeResponse(429, headers={"Retry-After": "86400"}))

    with pytest.raises(trip.NetworkError):
        http.get(URL)

    assert fake_clock.slept == []
    assert http.rate_limited == 1


def test_client_error_is_not_retried(tmp_path, fake_clock):
    http, session = make_http(tmp_path, FakeResponse(404))

    with pytest.raises(trip.NetworkError):
        http.get(URL)

    assert len(session.calls) == 1


def test_client_error_quotes_the_reason(tmp_path, fake_clock):
    reason = b'{"error": true, "reason": "Parameter start_date is out of range"}'
    http, _ = make_http(tmp_path, FakeResponse(400, reason))

    with pytest.raises(trip.NetworkError) as caught:
        http.get(URL)

    assert "HTTP 400" in str(caught.value)
    assert "start_date is out of range" in str(caught.value)


def test_sends_the_user_agent_and_reuses_the_cache(tmp_path, fake_clock):
    http, session = make_http(tmp_path, FakeResponse(200, b"data"))

    assert http.get(URL, params={"latitude": 45.9, "daily": "a,b"}) == b"data"
    assert session.calls[0][1]["User-Agent"] == AGENT
    assert session.calls[0][0] == URL + "?latitude=45.9&daily=a%2Cb"

    again, unused = make_http(tmp_path)
    assert again.get(URL, params={"latitude": 45.9, "daily": "a,b"}) == b"data"
    assert unused.calls == []
    assert again.cache_hits == 1


def test_pauses_after_a_download_but_not_after_a_cache_hit(tmp_path, fake_clock):
    http, _ = make_http(tmp_path, FakeResponse(200, b"data"))

    http.get(URL, pause=2)
    http.get(URL, pause=2)

    assert fake_clock.slept == [2]


def test_offline_mode_fails_without_a_cached_answer(tmp_path, fake_clock):
    http, session = make_http(tmp_path, offline=True)

    with pytest.raises(trip.NetworkError) as caught:
        http.get(URL)

    assert "offline" in str(caught.value)
    assert session.calls == []


def test_an_oversized_answer_is_refused_while_it_streams(tmp_path, fake_clock, monkeypatch):
    monkeypatch.setattr(trip, "MAX_ANSWER_BYTES", 10_000, raising=False)
    endless = EndlessBody()
    http, session = make_http(tmp_path, endless)

    with pytest.raises(trip.NetworkError) as caught:
        http.get(URL)

    assert "10,000 bytes" in str(caught.value)
    assert endless.served <= 10_000 + trip.CHUNK_BYTES
    assert endless.closed
    assert len(session.calls) == 1
    assert not http.cache_file(URL).exists()


def test_an_error_answer_is_read_only_as_far_as_its_quoted_start(tmp_path, fake_clock):
    endless = EndlessBody(404)
    http, _ = make_http(tmp_path, endless)

    with pytest.raises(trip.NetworkError) as caught:
        http.get(URL)

    assert "HTTP 404 (xxx" in str(caught.value)
    assert endless.served <= trip.CHUNK_BYTES
    assert endless.closed


@pytest.mark.parametrize("image_format", ["PNG", "JPEG", "WEBP"])
def test_tile_and_photo_formats_are_images(image_format):
    trip.image_answer(image_bytes((16, 16), image_format))


@pytest.mark.parametrize("image_format", ["BMP", "GIF", "TIFF", "ICO"])
def test_other_image_formats_are_refused(image_format):
    with pytest.raises(ValueError):
        trip.image_answer(image_bytes((16, 16), image_format))


def test_a_decompression_bomb_warning_is_an_error(monkeypatch):
    # Below twice the limit Pillow only warns and goes on to decode the whole image.
    monkeypatch.setattr(Image, "MAX_IMAGE_PIXELS", 1_000)

    with pytest.raises(ValueError, match="pixels"):
        trip.image_answer(image_bytes((40, 40), "PNG"))
