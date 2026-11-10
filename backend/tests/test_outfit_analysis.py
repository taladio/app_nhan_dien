"""Kiểm thử YOLO + Gemini bằng client giả, không gọi API thật."""

from __future__ import annotations

import json
from types import SimpleNamespace
from typing import Any

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

from backend import main
from backend.routers import outfit_analysis as router_module
from backend.schemas.outfit_analysis import (
    AnalysisContext,
    AnalysisPayload,
    DetectedItem,
    ModelOutfitEvaluation,
    SuggestedOutfit,
    UserProfile,
    calculate_overall_score,
    finalize_evaluation,
    rating_for_score,
)
from backend.services.color_detector import detect_clothing_colors
from backend.services.gemini_fashion_service import GeminiServiceError

client = TestClient(main.app)


def _encoded_image(extension: str = ".jpg") -> bytes:
    image = np.full((80, 100, 3), 255, dtype=np.uint8)
    ok, encoded = cv2.imencode(extension, image)
    assert ok
    return encoded.tobytes()


def _form() -> dict[str, str]:
    return {
        "height_cm": "170",
        "weight_kg": "65",
        "season": "summer",
        "temperature_c": "32",
        "style": "casual",
        "occasion": "school",
        "confidence": "0.25",
    }


class FakeModel:
    def __init__(self, *, has_detection: bool = True) -> None:
        self.has_detection = has_detection

    def predict(self, **_: Any) -> list[SimpleNamespace]:
        if self.has_detection:
            boxes = SimpleNamespace(
                xyxy=np.array([[10.0, 10.0, 90.0, 70.0]]),
                conf=np.array([0.91]),
                cls=np.array([0.0]),
            )
        else:
            boxes = SimpleNamespace(
                xyxy=np.empty((0, 4)),
                conf=np.array([]),
                cls=np.array([]),
            )
        return [SimpleNamespace(boxes=boxes)]


@pytest.fixture(autouse=True)
def fake_runtime(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(main.runtime, "model", FakeModel())
    monkeypatch.setattr(main.runtime, "names", {0: "T-Shirt"})
    monkeypatch.setattr(main.runtime, "device", "cpu")
    monkeypatch.setattr(main.runtime, "load_error", None)
    class FakeGeminiService:
        def evaluate(self, _: AnalysisPayload) -> ModelOutfitEvaluation:
            return _evaluation()

        def close(self) -> None:
            pass

    monkeypatch.setattr(
        router_module.GeminiFashionService,
        "from_environment",
        classmethod(lambda cls: FakeGeminiService()),
    )


def _evaluation(score: float = 80) -> ModelOutfitEvaluation:
    return ModelOutfitEvaluation(
        color_score=score,
        season_temperature_score=score,
        body_proportion_score=score,
        style_score=score,
        occasion_score=score,
        summary="Đánh giá thử nghiệm.",
        strengths=["Màu dễ phối."],
        problems=[],
        recommendations=["Giữ bảng màu gọn."],
        suggested_outfit=SuggestedOutfit(
            top="Áo thun trắng",
            bottom="Quần màu be",
            outerwear=None,
            shoes="Giày trắng",
            reason="Phù hợp bối cảnh.",
        ),
    )


def _payload() -> AnalysisPayload:
    return AnalysisPayload(
        detected_items=[
            DetectedItem(
                detection_id="det_1",
                class_id=0,
                raw_class_name="T-Shirt",
                class_name="tshirt",
                class_name_vi="Áo thun",
                primary_color="Trắng",
                secondary_colors=[],
                confidence=0.9,
                bbox={"x1": 1, "y1": 1, "x2": 20, "y2": 20},
            )
        ],
        user_profile=UserProfile(height_cm=170, weight_kg=65),
        context=AnalysisContext(
            season="summer",
            temperature_c=32,
            style="casual",
            occasion="school",
        ),
    )


def test_overall_score_uses_server_weights() -> None:
    evaluation = ModelOutfitEvaluation(
        **{
            **_evaluation().model_dump(),
            "color_score": 90,
            "season_temperature_score": 80,
            "body_proportion_score": 70,
            "style_score": 60,
            "occasion_score": 50,
        }
    )
    assert calculate_overall_score(evaluation) == 76.0


def test_missing_profile_and_weather_still_returns_yolo_and_partial_ai_scores() -> None:
    response = client.post(
        "/api/v1/outfit/analyze",
        data={"style": "casual", "occasion": "outing"},
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["detected_items"]
    assert data["source"] == "gemini"
    assert data["evaluation"]["season_temperature_score"] is None
    assert data["evaluation"]["body_proportion_score"] is None
    assert data["evaluation"]["overall_score"] == 80


def test_missing_evidence_is_excluded_from_score_weights() -> None:
    evaluation = _evaluation().model_copy(update={
        "color_score": None, "season_temperature_score": None,
        "body_proportion_score": None, "style_score": 90, "occasion_score": 70,
    })
    assert calculate_overall_score(evaluation) == 80


@pytest.mark.parametrize("field,value", [
    ("height_cm", "-1"), ("weight_kg", "nan"), ("temperature_c", "101"),
])
def test_optional_fields_still_reject_invalid_values(field: str, value: str) -> None:
    response = client.post(
        "/api/v1/outfit/analyze", data={**_form(), field: value},
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )
    assert response.status_code == 422


@pytest.mark.parametrize(
    ("score", "rating"),
    [
        (85, "Rất phù hợp"),
        (84.9, "Phù hợp"),
        (70, "Phù hợp"),
        (69.9, "Tạm ổn, nên điều chỉnh"),
        (50, "Tạm ổn, nên điều chỉnh"),
        (49.9, "Chưa phù hợp"),
    ],
)
def test_rating_thresholds(score: float, rating: str) -> None:
    assert rating_for_score(score) == rating


def test_color_detector_returns_primary_and_at_most_two_secondary_colors() -> None:
    image = np.zeros((100, 100, 3), dtype=np.uint8)
    image[:, :55] = (255, 0, 0)  # Xanh dương theo BGR.
    image[:, 55:80] = (255, 255, 255)
    image[:, 80:] = (0, 0, 255)

    primary, secondary = detect_clothing_colors(image)

    assert primary == "Xanh dương"
    assert len(secondary) <= 2
    assert "Trắng" in secondary


def test_missing_color_reweights_only_available_ai_scores() -> None:
    evaluation = ModelOutfitEvaluation(
        **{**_evaluation().model_dump(), "color_score": None}
    )
    assert calculate_overall_score(evaluation) == 80.0


def test_male_profile_with_skirt_is_not_marked_fully_suitable() -> None:
    payload = _payload().model_copy(deep=True)
    payload.user_profile.gender = "male"
    payload.detected_items[0].class_name = "skirt"
    payload.detected_items[0].class_name_vi = "Chân váy"
    evaluation = finalize_evaluation(_evaluation(95), payload)

    assert evaluation.overall_score == 69.0
    assert evaluation.rating == "Tạm ổn, nên điều chỉnh"
    assert "hồ sơ" in evaluation.summary
    assert any("giới tính Nam" in problem for problem in evaluation.problems)
    assert any("quần dài" in item for item in evaluation.recommendations)
    assert "Quần dài" in (evaluation.suggested_outfit.bottom or "")


def test_analyze_returns_no_detection_message(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(main.runtime, "model", FakeModel(has_detection=False))

    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 422
    assert response.json()["detail"] == router_module.NO_DETECTION_MESSAGE


def test_analyze_keeps_yolo_when_gemini_key_is_missing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def missing_key(_: object) -> None:
        raise GeminiServiceError(503, "Chưa cấu hình GEMINI_API_KEY trên backend.")

    monkeypatch.setattr(
        router_module.GeminiFashionService,
        "from_environment",
        classmethod(missing_key),
    )
    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["source"] == "unavailable"
    assert payload["detected_items"][0]["detection_id"] == "det_1"
    assert payload["detected_items"][0]["primary_color"] == "Trắng"
    assert payload["evaluation"] is None
    assert "GEMINI_API_KEY" in payload["ai_error"]


def test_weather_context_reaches_gemini_evaluation(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    received: list[AnalysisPayload] = []

    class CapturingGeminiService:
        def evaluate(self, payload: AnalysisPayload) -> ModelOutfitEvaluation:
            received.append(payload)
            return _evaluation()

        def close(self) -> None:
            pass

    monkeypatch.setattr(
        router_module.GeminiFashionService,
        "from_environment",
        classmethod(lambda cls: CapturingGeminiService()),
    )
    weather = {
        "source": "Open-Meteo", "temperature_c": 30, "apparent_temperature_c": 35,
        "precipitation_mm_current_interval": 0.4, "precipitation_interval_minutes": 15,
        "weather_code": 61, "temperature_max_c_today": 32,
        "temperature_min_c_today": 25, "precipitation_probability_max_percent_today": 80,
        "observed_at_local": "2026-09-28T14:15", "today_date": "2026-09-28",
        "timezone": "Asia/Ho_Chi_Minh",
    }
    response = client.post(
        "/api/v1/outfit/analyze",
        data={**_form(), "weather_json": json.dumps(weather), "gender": "male"},
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )
    assert response.status_code == 200
    assert received[0].context.weather is not None
    assert received[0].context.weather.source == "Open-Meteo"
    assert received[0].context.weather.precipitation_probability_max_percent_today == 80
    assert received[0].context.season is None
    assert received[0].context.temperature_c == 30
    assert received[0].user_profile.gender == "male"


def test_invalid_analysis_gender_returns_422() -> None:
    response = client.post(
        "/api/v1/outfit/analyze",
        data={**_form(), "gender": "arbitrary instruction"},
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )
    assert response.status_code == 422


def test_weather_analysis_accepts_no_manual_season(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: list[AnalysisPayload] = []

    class CapturingGeminiService:
        def evaluate(self, payload: AnalysisPayload) -> ModelOutfitEvaluation:
            captured.append(payload)
            return _evaluation()

        def close(self) -> None:
            pass

    monkeypatch.setattr(
        router_module.GeminiFashionService,
        "from_environment",
        classmethod(lambda cls: CapturingGeminiService()),
    )
    weather = {
        "source": "Open-Meteo", "temperature_c": 26,
        "apparent_temperature_c": 30,
        "precipitation_mm_current_interval": 0.9,
        "precipitation_interval_minutes": 15,
        "weather_code": 95, "temperature_max_c_today": 28,
        "temperature_min_c_today": 24,
        "precipitation_probability_max_percent_today": 100,
        "observed_at_local": "2026-10-08T15:00", "today_date": "2026-10-08",
        "timezone": "Asia/Ho_Chi_Minh",
    }
    form = _form()
    form.pop("season")
    form["temperature_c"] = "26"
    response = client.post(
        "/api/v1/outfit/analyze",
        data={**form, "weather_json": json.dumps(weather)},
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )
    assert response.status_code == 200
    assert captured[0].context.season is None
    assert captured[0].context.temperature_c == 26


def test_invalid_weather_context_returns_422() -> None:
    response = client.post(
        "/api/v1/outfit/analyze",
        data={**_form(), "weather_json": '{"source":"made-up"}'},
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )
    assert response.status_code == 422


def test_analyze_uses_mocked_gemini_and_recomputes_overall(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class FakeGeminiService:
        def evaluate(self, _: AnalysisPayload) -> ModelOutfitEvaluation:
            return _evaluation(88)

        def close(self) -> None:
            pass

    monkeypatch.setattr(
        router_module.GeminiFashionService,
        "from_environment",
        classmethod(lambda cls: FakeGeminiService()),
    )

    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 200
    assert response.json()["source"] == "gemini"
    assert response.json()["evaluation"]["overall_score"] == 88.0
    assert response.json()["evaluation"]["rating"] == "Rất phù hợp"


def test_analyze_does_not_fabricate_advice_when_gemini_raises(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class FailingGeminiService:
        def evaluate(self, _: AnalysisPayload) -> ModelOutfitEvaluation:
            raise GeminiServiceError(504, "Gemini phản hồi quá chậm. Hãy thử lại.")

        def close(self) -> None:
            pass

    monkeypatch.setattr(
        router_module.GeminiFashionService,
        "from_environment",
        classmethod(lambda cls: FailingGeminiService()),
    )

    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 200
    assert response.json()["source"] == "unavailable"
    assert response.json()["evaluation"] is None
    assert response.json()["detected_items"]
    assert "quá chậm" in response.json()["ai_error"]


def test_analysis_endpoint_rejects_webp() -> None:
    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.webp", _encoded_image(".webp"), "image/webp")},
    )

    assert response.status_code == 400
    assert "JPG" in response.json()["detail"]
