"""Schema dữ liệu cho luồng YOLO + đánh giá phối đồ."""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

Season = Literal["spring", "summer", "autumn", "winter", "rainy"]
Style = Literal["casual", "sporty", "elegant", "office", "streetwear", "minimal", "party"]
Occasion = Literal["school", "work", "outing", "date", "party", "sport", "travel"]
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
    height_cm: float = Field(gt=0, le=300)
    weight_kg: float = Field(gt=0, le=500)


class AnalysisContext(StrictModel):
    season: Season
    temperature_c: float = Field(ge=-100, le=100)
    style: Style
    occasion: Occasion


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
    color_score: Score
    season_temperature_score: Score
    body_proportion_score: Score
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
    source: Literal["openai", "fallback"]
    detected_items: list[DetectedItem] = Field(min_length=1)
    evaluation: OutfitEvaluation


def calculate_overall_score(evaluation: ModelOutfitEvaluation) -> float:
    score = (
        evaluation.color_score * 0.30
        + evaluation.season_temperature_score * 0.30
        + evaluation.body_proportion_score * 0.20
        + evaluation.style_score * 0.10
        + evaluation.occasion_score * 0.10
    )
    return round(score, 1)


def rating_for_score(score: float) -> str:
    if score >= 85:
        return "Rất phù hợp"
    if score >= 70:
        return "Phù hợp"
    if score >= 50:
        return "Tạm ổn, nên điều chỉnh"
    return "Chưa phù hợp"


def finalize_evaluation(evaluation: ModelOutfitEvaluation) -> OutfitEvaluation:
    overall_score = calculate_overall_score(evaluation)
    return OutfitEvaluation(
        **evaluation.model_dump(),
        overall_score=overall_score,
        rating=rating_for_score(overall_score),
    )
