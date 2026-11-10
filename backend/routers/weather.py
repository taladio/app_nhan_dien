"""Thời tiết Open-Meteo cho gợi ý phối đồ; không chạy trong luồng camera."""

from __future__ import annotations

import math
from datetime import date, datetime
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/weather", tags=["weather"])
OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"


class WeatherLocationRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(label)
    return float(value)


def _first_number(group: dict[str, Any], key: str) -> float:
    values = group[key]
    if not isinstance(values, list) or not values:
        raise ValueError(key)
    return _number(values[0], key)


def parse_open_meteo(payload: Any, latitude: float, longitude: float) -> dict[str, Any]:
    """Chỉ trả trường có thật; thiếu trường bắt buộc thì báo lỗi upstream."""
    try:
        if not isinstance(payload, dict):
            raise ValueError("payload")
        current = payload["current"]
        daily = payload["daily"]
        if not isinstance(current, dict) or not isinstance(daily, dict):
            raise ValueError("groups")
        observed_at = current["time"]
        if not isinstance(observed_at, str):
            raise ValueError("time")
        datetime.fromisoformat(observed_at)
        dates = daily["time"]
        if not isinstance(dates, list) or not dates or not isinstance(dates[0], str):
            raise ValueError("daily.time")
        date.fromisoformat(dates[0])
        timezone = payload["timezone"]
        if not isinstance(timezone, str) or not timezone:
            raise ValueError("timezone")
        interval = _number(current["interval"], "interval")
        if interval <= 0:
            raise ValueError("interval")
        weather_code = _number(current["weather_code"], "weather_code")
        probability = _first_number(daily, "precipitation_probability_max")
        precipitation = _number(current["precipitation"], "precipitation")
        maximum = _first_number(daily, "temperature_2m_max")
        minimum = _first_number(daily, "temperature_2m_min")
        if (weather_code != int(weather_code) or not 0 <= weather_code <= 99
                or not 0 <= probability <= 100 or precipitation < 0 or maximum < minimum):
            raise ValueError("out of range")
        return {
            "source": "Open-Meteo",
            "latitude": latitude,
            "longitude": longitude,
            "timezone": timezone,
            "observed_at_local": observed_at,
            "today_date": dates[0],
            "temperature_c": _number(current["temperature_2m"], "temperature_2m"),
            "apparent_temperature_c": _number(current["apparent_temperature"], "apparent_temperature"),
            "precipitation_mm_current_interval": precipitation,
            "precipitation_interval_minutes": interval / 60,
            "weather_code": int(weather_code),
            "temperature_max_c_today": maximum,
            "temperature_min_c_today": minimum,
            "precipitation_probability_max_percent_today": int(probability),
        }
    except (KeyError, TypeError, ValueError, OverflowError) as error:
        raise HTTPException(status_code=502, detail="Dữ liệu Open-Meteo thiếu trường hoặc không hợp lệ.") from error


async def fetch_open_meteo(
    latitude: float, longitude: float, *, client: httpx.AsyncClient | None = None
) -> dict[str, Any]:
    params = {
        "latitude": latitude,
        "longitude": longitude,
        "current": "temperature_2m,apparent_temperature,precipitation,weather_code",
        "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        "timezone": "auto",
        "forecast_days": 1,
        "temperature_unit": "celsius",
        "precipitation_unit": "mm",
    }
    try:
        if client is None:
            async with httpx.AsyncClient(timeout=8.0) as owned_client:
                response = await owned_client.get(OPEN_METEO_URL, params=params)
        else:
            response = await client.get(OPEN_METEO_URL, params=params, timeout=8.0)
    except httpx.TimeoutException as error:
        raise HTTPException(status_code=504, detail="Open-Meteo phản hồi quá chậm. Hãy thử lại.") from error
    except httpx.RequestError as error:
        raise HTTPException(status_code=502, detail="Không thể kết nối Open-Meteo lúc này.") from error

    if response.status_code == 429:
        raise HTTPException(status_code=503, detail="Open-Meteo đang giới hạn yêu cầu. Hãy thử lại sau.")
    if response.status_code != 200:
        raise HTTPException(status_code=502, detail="Open-Meteo tạm thời không phản hồi.")
    try:
        payload = response.json()
    except ValueError as error:
        raise HTTPException(status_code=502, detail="Open-Meteo trả dữ liệu không phải JSON.") from error
    return parse_open_meteo(payload, latitude, longitude)


@router.post("/current")
async def current_weather(
    location: WeatherLocationRequest,
) -> dict[str, Any]:
    return await fetch_open_meteo(location.latitude, location.longitude)
