"""Validated metadata-only requests for Gemini outfit advice and chat."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

try:
    from .outfit_analysis import Gender, Occasion, Season, Style, WeatherContext
except ImportError:  # pragma: no cover - supports running from backend/
    from schemas.outfit_analysis import Gender, Occasion, Season, Style, WeatherContext


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class ClothingItem(StrictModel):
    # The raw name comes from YOLO model.names, not a fixed list of app groups.
    label: str = Field(min_length=1, max_length=80)
    confidence: float | None = Field(default=None, ge=0, le=1)
    color: str | None = Field(default=None, min_length=1, max_length=40)


class OutfitContext(StrictModel):
    # Danh sách rỗng nghĩa là người dùng muốn gợi ý trước khi chụp ảnh.
    items: list[ClothingItem] = Field(default_factory=list, max_length=30)
    weather: WeatherContext | None = None
    season: Season | None = None
    style: Style | None = None
    occasion: Occasion | None = None
    temperature_c: float | None = Field(default=None, ge=-100, le=100)
    height_cm: float | None = Field(default=None, gt=0, le=300)
    weight_kg: float | None = Field(default=None, gt=0, le=500)
    gender: Gender | None = None

    @model_validator(mode="after")
    def remove_unknown_colors(self) -> "OutfitContext":
        if self.weather is not None:
            # Open-Meteo không cung cấp mùa: không ghép mùa/nhiệt độ thủ công.
            self.season = None
            self.temperature_c = self.weather.temperature_c
        for item in self.items:
            if item.color and item.color.casefold() in {
                "không xác định", "unknown", "n/a"
            }:
                item.color = None
        return self

    @property
    def has_color_data(self) -> bool:
        return any(item.color is not None for item in self.items)


class GeminiSuggestionRequest(StrictModel):
    context: OutfitContext


class GeminiSuggestion(StrictModel):
    assessment: str = Field(min_length=1, max_length=200)
    reason: str = Field(min_length=1, max_length=300)
    adjustments: list[str] = Field(min_length=1, max_length=3)
    color_score: int | None = Field(default=None, ge=0, le=100)

    @model_validator(mode="after")
    def validate_adjustments(self) -> "GeminiSuggestion":
        if any(not text.strip() or len(text) > 160 for text in self.adjustments):
            raise ValueError("adjustments must be 1-160 characters each")
        return self


class ChatTurn(StrictModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=2000)


class GeminiChatRequest(StrictModel):
    context: OutfitContext
    message: str = Field(min_length=1, max_length=500)
    history: list[ChatTurn] = Field(default_factory=list, max_length=12)


class GeminiChatReply(StrictModel):
    reply: str = Field(min_length=1, max_length=2000)
