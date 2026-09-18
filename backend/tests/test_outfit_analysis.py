"""Kiểm thử endpoint outfit analysis không gọi OpenAI hoặc YOLO thật."""

from __future__ import annotations

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
    rating_for_score,
)
from backend.services.color_detector import detect_clothing_colors
from backend.services.rule_based_outfit_service import evaluate_with_rules

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
    monkeypatch.setenv("OPENAI_API_KEY", "")


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


def test_rule_based_evaluation_works_without_api_key() -> None:
    evaluation = evaluate_with_rules(_payload())
    assert 0 <= calculate_overall_score(evaluation) <= 100
    assert evaluation.suggested_outfit.reason


def test_analyze_returns_no_detection_message(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(main.runtime, "model", FakeModel(has_detection=False))

    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 422
    assert response.json()["detail"] == router_module.NO_DETECTION_MESSAGE


def test_analyze_falls_back_when_api_key_is_missing() -> None:
    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["source"] == "fallback"
    assert payload["detected_items"][0]["detection_id"] == "det_1"
    assert payload["detected_items"][0]["primary_color"] == "Trắng"
    assert 0 <= payload["evaluation"]["overall_score"] <= 100


def test_analyze_uses_mocked_openai_and_recomputes_overall(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class FakeOpenAIService:
        def evaluate(self, _: AnalysisPayload) -> ModelOutfitEvaluation:
            return _evaluation(88)

    monkeypatch.setattr(
        router_module.OpenAIOutfitService,
        "from_environment",
        classmethod(lambda cls: FakeOpenAIService()),
    )

    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 200
    assert response.json()["source"] == "openai"
    assert response.json()["evaluation"]["overall_score"] == 88.0
    assert response.json()["evaluation"]["rating"] == "Rất phù hợp"


def test_analyze_falls_back_when_openai_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    class FailingOpenAIService:
        def evaluate(self, _: AnalysisPayload) -> ModelOutfitEvaluation:
            raise TimeoutError("simulated")

    monkeypatch.setattr(
        router_module.OpenAIOutfitService,
        "from_environment",
        classmethod(lambda cls: FailingOpenAIService()),
    )

    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 200
    assert response.json()["source"] == "fallback"


def test_analysis_endpoint_rejects_webp() -> None:
    response = client.post(
        "/api/v1/outfit/analyze",
        data=_form(),
        files={"file": ("outfit.webp", _encoded_image(".webp"), "image/webp")},
    )

    assert response.status_code == 400
    assert "JPG" in response.json()["detail"]
