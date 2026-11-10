"""Open-Meteo proxy: tọa độ, dữ liệu, timeout và lỗi upstream."""

from __future__ import annotations

import asyncio

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.routers import weather


app = FastAPI()
app.include_router(weather.router)
client = TestClient(app)


def test_invalid_coordinates_are_rejected() -> None:
    response = client.post("/api/v1/weather/current", json={"latitude": 100, "longitude": 108.2})
    assert response.status_code == 422


def test_valid_coordinates_reach_existing_router(monkeypatch) -> None:
    async def fake_fetch(latitude: float, longitude: float):
        assert (latitude, longitude) == (16.1, 108.2)
        return {"source": "Open-Meteo", "temperature_c": 30.0}

    monkeypatch.setattr(weather, "fetch_open_meteo", fake_fetch)
    response = client.post("/api/v1/weather/current", json={"latitude": 16.1, "longitude": 108.2})
    assert response.status_code == 200
    assert response.json() == {"source": "Open-Meteo", "temperature_c": 30.0}


def _upstream_response() -> dict:
    return {
        "timezone": "Asia/Ho_Chi_Minh",
        "current": {
            "time": "2026-09-28T14:15",
            "interval": 900,
            "temperature_2m": 30.1,
            "apparent_temperature": 35.2,
            "precipitation": 0.4,
            "weather_code": 61,
        },
        "daily": {
            "time": ["2026-09-28"],
            "temperature_2m_max": [32.0],
            "temperature_2m_min": [25.0],
            "precipitation_probability_max": [80],
        },
        "unused": "ignored",
    }


def test_open_meteo_fields_and_units() -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.host == "api.open-meteo.com"
        assert request.url.params["current"] == "temperature_2m,apparent_temperature,precipitation,weather_code"
        assert request.url.params["daily"] == "temperature_2m_max,temperature_2m_min,precipitation_probability_max"
        assert request.url.params["timezone"] == "auto"
        assert request.url.params["forecast_days"] == "1"
        assert "apikey" not in request.url.params
        return httpx.Response(200, json=_upstream_response())

    async def fetch() -> dict:
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as upstream:
            return await weather.fetch_open_meteo(16.1, 108.2, client=upstream)

    payload = asyncio.run(fetch())
    assert payload["temperature_c"] == 30.1
    assert payload["apparent_temperature_c"] == 35.2
    assert payload["precipitation_mm_current_interval"] == 0.4
    assert payload["precipitation_interval_minutes"] == 15
    assert payload["precipitation_probability_max_percent_today"] == 80
    assert payload["weather_code"] == 61
    assert payload["source"] == "Open-Meteo"
    assert "unused" not in payload


def test_upstream_failure_has_no_fake_weather() -> None:
    async def fetch() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(500))) as upstream:
            await weather.fetch_open_meteo(16.1, 108.2, client=upstream)

    with pytest.raises(Exception) as caught:
        asyncio.run(fetch())
    assert getattr(caught.value, "status_code", None) == 502


def test_missing_weather_field_is_rejected() -> None:
    invalid = _upstream_response()
    del invalid["current"]["apparent_temperature"]
    async def fetch() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json=invalid))) as upstream:
            await weather.fetch_open_meteo(16.1, 108.2, client=upstream)

    with pytest.raises(Exception) as caught:
        asyncio.run(fetch())
    assert getattr(caught.value, "status_code", None) == 502
