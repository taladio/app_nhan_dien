"""Bộ chấm điểm cục bộ để ứng dụng luôn demo được khi OpenAI không sẵn sàng."""

from __future__ import annotations

try:
    from ..schemas.outfit_analysis import (
        AnalysisPayload,
        ModelOutfitEvaluation,
        SuggestedOutfit,
    )
except ImportError:  # Hỗ trợ `cd backend`.
    from schemas.outfit_analysis import AnalysisPayload, ModelOutfitEvaluation, SuggestedOutfit

NEUTRAL_COLORS = {"Đen", "Trắng", "Xám", "Nâu", "Be"}
WARM_COLORS = {"Đỏ", "Cam", "Vàng", "Hồng", "Nâu", "Be"}
COOL_COLORS = {"Xanh lá", "Xanh ngọc", "Xanh dương", "Tím"}

STYLE_ITEMS: dict[str, set[str]] = {
    "casual": {"tshirt", "shirt", "pants", "shorts", "skirt", "dress", "shoes"},
    "sporty": {"tshirt", "shorts", "pants", "shoes"},
    "elegant": {"shirt", "jacket", "pants", "skirt", "dress", "shoes"},
    "office": {"shirt", "jacket", "pants", "skirt", "dress", "shoes"},
    "streetwear": {"tshirt", "jacket", "pants", "shorts", "shoes"},
    "minimal": {"tshirt", "shirt", "pants", "skirt", "dress", "shoes"},
    "party": {"shirt", "jacket", "skirt", "dress", "shoes"},
}

OCCASION_ITEMS: dict[str, set[str]] = {
    "school": {"tshirt", "shirt", "jacket", "pants", "skirt", "shoes"},
    "work": {"shirt", "jacket", "pants", "skirt", "dress", "shoes"},
    "outing": {"tshirt", "shirt", "pants", "shorts", "skirt", "dress", "shoes"},
    "date": {"shirt", "jacket", "pants", "skirt", "dress", "shoes"},
    "party": {"shirt", "jacket", "skirt", "dress", "shoes"},
    "sport": {"tshirt", "shorts", "pants", "shoes"},
    "travel": {"tshirt", "shirt", "jacket", "pants", "shorts", "shoes"},
}


def _clamp_score(value: float) -> float:
    return round(min(max(value, 0), 100), 1)


def _color_score(colors: list[str]) -> tuple[float, str]:
    known = [color for color in colors if color != "Không xác định"]
    if not known:
        return 60, "Màu sắc chưa đủ rõ để đánh giá chắc chắn."
    unique = set(known)
    score = 72.0
    if unique & NEUTRAL_COLORS:
        score += 12
    if unique <= NEUTRAL_COLORS:
        score += 5
    if unique & WARM_COLORS and unique & COOL_COLORS and not unique & NEUTRAL_COLORS:
        score -= 8
    if len(unique) > 4:
        score -= 10
    return _clamp_score(score), "Bảng màu có điểm neo trung tính, tương đối dễ phối."


def _season_temperature_score(classes: set[str], season: str, temperature: float) -> tuple[float, str | None]:
    score = 75.0
    problem: str | None = None
    if temperature > 28:
        if "jacket" in classes:
            score -= 24
            problem = "Áo khoác có thể chưa thuận tiện trong thời tiết trên 28°C."
        if classes & {"tshirt", "shirt", "shorts", "skirt", "dress"}:
            score += 10
    elif temperature < 18:
        if "jacket" in classes:
            score += 14
        else:
            score -= 18
            problem = "Nên cân nhắc thêm áo khoác khi nhiệt độ dưới 18°C."
        if "pants" in classes:
            score += 6

    if season == "summer" and classes & {"tshirt", "shirt", "shorts", "skirt", "dress"}:
        score += 7
    if season == "winter" and {"jacket", "pants"}.issubset(classes):
        score += 10
    if season == "rainy" and classes & {"pants", "shorts", "shoes"}:
        score += 5
    return _clamp_score(score), problem


def _match_score(classes: set[str], preferred: set[str]) -> float:
    if not classes:
        return 50
    return _clamp_score(55 + 40 * len(classes & preferred) / len(classes))


def evaluate_with_rules(payload: AnalysisPayload) -> ModelOutfitEvaluation:
    classes = {item.class_name for item in payload.detected_items}
    colors = [item.primary_color for item in payload.detected_items]
    context = payload.context
    weather = context.weather
    effective_temperature = weather.temperature_c if weather else context.temperature_c

    color_score, color_strength = _color_score(colors)
    season_score, temperature_problem = _season_temperature_score(
        classes, context.season, effective_temperature
    )
    style_score = _match_score(classes, STYLE_ITEMS[context.style])
    occasion_score = _match_score(classes, OCCASION_ITEMS[context.occasion])
    body_score = 78.0 if classes & {"pants", "shorts", "skirt", "dress"} else 70.0

    strengths = [color_strength]
    if season_score >= 78:
        strengths.append("Các nhóm trang phục nhìn chung phù hợp mùa và mức nhiệt đã chọn.")
    if style_score >= 80:
        strengths.append("Các món nhận diện được khá sát phong cách mong muốn.")

    problems: list[str] = []
    if temperature_problem:
        problems.append(temperature_problem)
    if style_score < 75:
        problems.append("Một vài món chưa thể hiện rõ phong cách đã chọn.")
    if occasion_score < 75:
        problems.append("Cách phối hiện tại chưa thật sự sát hoàn cảnh đã chọn.")

    recommendations = [
        "Giữ tỷ lệ tổng thể cân đối bằng cách chọn độ dài áo và quần/váy bổ trợ nhau.",
        "Ưu tiên một màu trung tính làm nền nếu muốn bộ đồ dễ kết hợp hơn.",
    ]
    if temperature_problem:
        recommendations.insert(0, temperature_problem.replace("có thể chưa", "nên được điều chỉnh để"))

    warm_weather = effective_temperature > 28 or context.season == "summer"
    cold_weather = effective_temperature < 18 or context.season == "winter"
    rain_risk = bool(weather and (
        weather.precipitation_mm_current_interval > 0
        or weather.precipitation_probability_max_percent_today >= 60
        or weather.weather_code in {51, 53, 55, 61, 63, 65, 80, 81, 82, 95, 96, 99}
    ))
    if rain_risk:
        recommendations.insert(0, "Mang lớp ngoài chống mưa và chọn giày đế bám; lượng mưa hiện tại khác xác suất mưa trong ngày.")
    suggested = SuggestedOutfit(
        top="Áo thun hoặc áo sơ mi màu sáng, kiểu dáng gọn" if warm_weather else "Áo có độ dài cân đối, màu trung tính",
        bottom="Quần short hoặc chân váy màu be" if warm_weather else "Quần dài hoặc chân váy màu trung tính",
        outerwear="Áo khoác chống mưa mỏng" if rain_risk else ("Áo khoác có thể phối lớp" if cold_weather else None),
        shoes="Giày đế bám, hạn chế thấm nước" if rain_risk else "Giày có màu lặp lại một màu trong bộ đồ",
        reason="Gợi ý dựa trên đồ YOLO nhận diện, bối cảnh và dữ liệu Open-Meteo." if weather else "Gợi ý ưu tiên sự cân đối, bối cảnh sử dụng và mức nhiệt người dùng đã chọn.",
    )

    return ModelOutfitEvaluation(
        color_score=color_score,
        season_temperature_score=season_score,
        body_proportion_score=body_score,
        style_score=style_score,
        occasion_score=occasion_score,
        summary="Đây là đánh giá cơ bản dựa trên loại trang phục, màu và bối cảnh đã nhập.",
        strengths=strengths,
        problems=problems,
        recommendations=recommendations,
        suggested_outfit=suggested,
    )
