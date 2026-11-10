"""Schema dữ liệu cho luồng YOLO + đánh giá phối đồ."""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Season = Literal["spring", "summer", "autumn", "winter", "rainy"]
Style = Literal["casual", "sporty", "elegant", "office", "streetwear", "minimal", "party"]
Occasion = Literal["school", "work", "outing", "date", "party", "sport", "travel"]
Gender = Literal["male", "female", "other"]
Score = Annotated[float, Field(ge=0, le=100)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class BoundingBox(StrictModel):
    x1: int = Field(ge=0)
    y1: int = Field(ge=0)
    x2: int = Field(gt=0)
    y2: int = Field(gt=0)


class DetectedItem(StrictModel):
    detection_id: str = Field(min_length=1)
    class_id: int = Field(ge=0)
    raw_class_name: str = Field(min_length=1)
    class_name: Literal["tshirt", "shirt", "jacket", "pants", "shorts", "skirt", "dress", "shoes"]
    class_name_vi: str = Field(min_length=1)
    primary_color: str = Field(min_length=1)
    secondary_colors: list[str] = Field(max_length=2)
    confidence: float = Field(ge=0, le=1)
    bbox: BoundingBox


class UserProfile(StrictModel):
    height_cm: float | None = Field(default=None, gt=0, le=300)
    weight_kg: float | None = Field(default=None, gt=0, le=500)
    gender: Gender | None = None


class WeatherContext(StrictModel):
    source: Literal["Open-Meteo"]
    temperature_c: float = Field(ge=-100, le=100)
    apparent_temperature_c: float = Field(ge=-100, le=100)
    precipitation_mm_current_interval: float = Field(ge=0, le=10000)
    precipitation_interval_minutes: float = Field(gt=0, le=1440)
    weather_code: int = Field(ge=0, le=99)
    temperature_max_c_today: float = Field(ge=-100, le=100)
    temperature_min_c_today: float = Field(ge=-100, le=100)
    precipitation_probability_max_percent_today: int = Field(ge=0, le=100)
    observed_at_local: str = Field(min_length=1, max_length=64)
    today_date: str = Field(min_length=1, max_length=16)
    timezone: str = Field(min_length=1, max_length=80)


class AnalysisContext(StrictModel):
    season: Season | None = None
    temperature_c: float | None = Field(default=None, ge=-100, le=100)
    style: Style
    occasion: Occasion
    weather: WeatherContext | None = None


class AnalysisPayload(StrictModel):
    detected_items: list[DetectedItem] = Field(min_length=1)
    user_profile: UserProfile
    context: AnalysisContext


class SuggestedOutfit(StrictModel):
    top: str | None
    bottom: str | None
    outerwear: str | None
    shoes: str | None
    reason: str = Field(min_length=1)


class ModelOutfitEvaluation(StrictModel):
    color_score: Score | None
    season_temperature_score: Score | None
    body_proportion_score: Score | None
    style_score: Score
    occasion_score: Score
    summary: str = Field(min_length=1)
    strengths: list[str]
    problems: list[str]
    recommendations: list[str]
    suggested_outfit: SuggestedOutfit


class OutfitEvaluation(ModelOutfitEvaluation):
    overall_score: Score
    rating: Literal[
        "Rất phù hợp",
        "Phù hợp",
        "Tạm ổn, nên điều chỉnh",
        "Chưa phù hợp",
    ]


class OutfitAnalysisResponse(StrictModel):
    filename: str
    image_width: int = Field(gt=0)
    image_height: int = Field(gt=0)
    source: Literal["gemini", "unavailable"]
    detected_items: list[DetectedItem] = Field(min_length=1)
    evaluation: OutfitEvaluation | None = None
    ai_error: str | None = None

    @model_validator(mode="after")
    def validate_ai_state(self) -> "OutfitAnalysisResponse":
        if self.source == "gemini" and self.evaluation is None:
            raise ValueError("Gemini response requires an evaluation")
        if self.source == "unavailable" and (self.evaluation is not None or not self.ai_error):
            raise ValueError("Unavailable AI response requires an error and no evaluation")
        return self


def calculate_overall_score(evaluation: ModelOutfitEvaluation) -> float:
    scores = (
        (evaluation.color_score, 0.30),
        (evaluation.season_temperature_score, 0.30),
        (evaluation.body_proportion_score, 0.20),
        (evaluation.style_score, 0.10),
        (evaluation.occasion_score, 0.10),
    )
    # Missing evidence is not a zero score; normalize only known criteria.
    weight = sum(weight for score, weight in scores if score is not None)
    return round(sum(score * weight for score, weight in scores
                     if score is not None) / weight, 1)


def rating_for_score(score: float) -> str:
    if score >= 85:
        return "Rất phù hợp"
    if score >= 70:
        return "Phù hợp"
    if score >= 50:
        return "Tạm ổn, nên điều chỉnh"
    return "Chưa phù hợp"


def finalize_evaluation(
    evaluation: ModelOutfitEvaluation,
    payload: AnalysisPayload | None = None,
) -> OutfitEvaluation:
    adjusted = evaluation.model_copy(deep=True)
    if payload is not None:
        context = payload.context
        if context.weather is None and context.temperature_c is None and context.season is None:
            adjusted.season_temperature_score = None
        if payload.user_profile.height_cm is None or payload.user_profile.weight_kg is None:
            adjusted.body_proportion_score = None
    profile_mismatch = None
    if payload is not None and payload.user_profile.gender == "male":
        feminine_items = [
            item.class_name_vi
            for item in payload.detected_items
            if item.class_name in {"skirt", "dress"}
        ]
        if feminine_items:
            profile_mismatch = ", ".join(dict.fromkeys(feminine_items))
            problem = (
                f"{profile_mismatch} chưa khớp với lựa chọn giới tính Nam "
                "trong hồ sơ."
            )
            recommendation = (
                "Nếu muốn cách phối nam tính hơn, thay bằng quần dài hoặc quần "
                "short; vẫn có thể giữ món hiện tại nếu đây là phong cách bạn "
                "chủ động chọn."
            )
            adjusted.summary = (
                f"Cần điều chỉnh: {profile_mismatch} chưa phù hợp với ưu tiên "
                "phối đồ Nam trong hồ sơ."
            )
            adjusted.problems = [problem, *adjusted.problems]
            adjusted.recommendations = [recommendation, *adjusted.recommendations]
            adjusted.style_score = min(adjusted.style_score, 49)
            adjusted.suggested_outfit.bottom = "Quần dài hoặc quần short phù hợp"
            adjusted.suggested_outfit.reason = (
                "Phương án thay thế khớp hơn với giới tính Nam đã chọn trong hồ sơ."
            )

    overall_score = calculate_overall_score(adjusted)
    if profile_mismatch is not None:
        # Không để kết quả Nam + chân váy/váy tiếp tục mang nhãn “Phù hợp”.
        overall_score = min(overall_score, 69.0)
    return OutfitEvaluation(
        **adjusted.model_dump(),
        overall_score=overall_score,
        rating=rating_for_score(overall_score),
    )
