"""Kiểm thử API không phụ thuộc vào file best.pt thật."""

from __future__ import annotations

import os
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

# Bắt buộc backend đi qua nhánh thiếu model trong tiến trình test. Suy luận thành
# công được kiểm tra bằng FakeModel để test ổn định trên máy không có GPU/model.
os.environ["MODEL_PATH"] = str(Path(__file__).with_name("model-khong-ton-tai.pt"))

from backend import main  # noqa: E402


client = TestClient(main.app)


@pytest.fixture(autouse=True)
def reset_runtime(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(main.runtime, "model", None)
    monkeypatch.setattr(main.runtime, "names", {})
    monkeypatch.setattr(main.runtime, "load_error", "Không tìm thấy mô hình.")
    monkeypatch.setattr(main.runtime, "device", "cpu")


def _encoded_image(extension: str = ".jpg") -> bytes:
    image = np.full((80, 100, 3), 255, dtype=np.uint8)
    ok, encoded = cv2.imencode(extension, image)
    assert ok
    return encoded.tobytes()


def test_root_returns_200() -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {
        "message": "Fashion AI API đang hoạt động",
        "documentation": "/docs",
    }


def test_health_has_required_structure() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "degraded"
    assert payload["model_loaded"] is False
    assert isinstance(payload["model_path"], str)
    assert payload["device"] == "cpu"
    assert payload["number_of_model_classes"] == 0


def test_classes_always_contains_eight_application_classes() -> None:
    response = client.get("/api/v1/classes")

    assert response.status_code == 200
    application_classes = response.json()["application_classes"]
    assert len(application_classes) == 8
    assert {item["class_name"] for item in application_classes} == set(main.APP_CLASSES)
    assert all(item["class_name_vi"] for item in application_classes)


def test_rejects_non_image_file() -> None:
    response = client.post(
        "/api/v1/detect",
        files={"file": ("note.txt", b"khong phai anh", "text/plain")},
    )

    assert response.status_code == 400
    assert "MIME type" in response.json()["detail"]


def test_rejects_empty_file() -> None:
    response = client.post(
        "/api/v1/detect",
        files={"file": ("empty.jpg", b"", "image/jpeg")},
    )

    assert response.status_code == 400
    assert "không được để trống" in response.json()["detail"]


def test_rejects_fake_image_content() -> None:
    response = client.post(
        "/api/v1/detect",
        files={"file": ("fake.jpg", b"day khong phai jpeg", "image/jpeg")},
    )

    assert response.status_code == 400
    assert "không phải là ảnh hợp lệ" in response.json()["detail"]


@pytest.mark.parametrize("confidence", [-0.01, 1.01])
def test_rejects_confidence_outside_valid_range(confidence: float) -> None:
    response = client.post(
        f"/api/v1/detect?confidence={confidence}",
        files={"file": ("valid.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 422


def test_detect_returns_503_when_model_is_missing() -> None:
    response = client.post(
        "/api/v1/detect",
        files={"file": ("valid.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 503
    assert "backend/models/best.pt" in response.json()["detail"]


class FakeModel:
    def __init__(self) -> None:
        self.last_kwargs: dict[str, Any] = {}

    def predict(self, **kwargs: Any) -> list[SimpleNamespace]:
        self.last_kwargs = kwargs
        boxes = SimpleNamespace(
            # Bag phải bị lọc; bbox T-Shirt phải được clamp theo ảnh 100x80.
            xyxy=np.array(
                [
                    [5.0, 5.0, 40.0, 40.0],
                    [-10.0, -7.0, 120.0, 90.0],
                    [10.0, 20.0, 50.0, 70.0],
                    [60.0, 20.0, 90.0, 70.0],
                ]
            ),
            conf=np.array([0.99, 0.40123, 0.90127, 0.70129]),
            cls=np.array([1.0, 0.0, 2.0, 2.0]),
        )
        return [SimpleNamespace(boxes=boxes)]


def test_mocked_yolo_result_is_filtered_clamped_sorted_and_summarized(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake_model = FakeModel()
    monkeypatch.setattr(main.runtime, "model", fake_model)
    monkeypatch.setattr(main.runtime, "names", {0: "T-Shirt", 1: "Bag", 2: "Shoes"})
    monkeypatch.setattr(main.runtime, "load_error", None)

    response = client.post(
        "/api/v1/detect?confidence=0.3&iou=0.5",
        files={"file": ("outfit.jpg", _encoded_image(), "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["filename"] == "outfit.jpg"
    assert payload["image_width"] == 100
    assert payload["image_height"] == 80
    assert payload["detection_count"] == 3
    assert payload["ignored_detection_count"] == 1

    detections = payload["detections"]
    assert [item["confidence"] for item in detections] == [0.9013, 0.7013, 0.4012]
    assert [item["class_name"] for item in detections] == ["shoes", "shoes", "tshirt"]
    assert all(item["class_name"] != "bag" for item in detections)

    tshirt = detections[-1]
    assert tshirt["raw_class_name"] == "T-Shirt"
    assert tshirt["class_name_vi"] == "Áo thun"
    assert tshirt["bbox"] == {"x1": 0, "y1": 0, "x2": 100, "y2": 80}
    assert tshirt["bbox_normalized"] == {"x1": 0.0, "y1": 0.0, "x2": 1.0, "y2": 1.0}

    summary_by_class = {item["class_name"]: item["count"] for item in payload["summary"]}
    assert summary_by_class == {"tshirt": 1, "shoes": 2}

    assert fake_model.last_kwargs["imgsz"] == 640
    assert fake_model.last_kwargs["conf"] == 0.3
    assert fake_model.last_kwargs["iou"] == 0.5
    assert fake_model.last_kwargs["verbose"] is False
    assert fake_model.last_kwargs["device"] == "cpu"


def test_invalid_zero_area_box_is_dropped() -> None:
    boxes = SimpleNamespace(
        xyxy=np.array([[20.0, 20.0, 20.0, 30.0]]),
        conf=np.array([0.8]),
        cls=np.array([0.0]),
    )
    image = np.zeros((50, 50, 3), dtype=np.uint8)

    detections, ignored_count = main.process_yolo_results(
        [SimpleNamespace(boxes=boxes)], image, {0: "shirt"}
    )

    assert detections == []
    assert ignored_count == 1


@pytest.mark.parametrize(
    ("raw_name", "expected"),
    [
        ("t-shirt", "tshirt"),
        ("Blouse", "shirt"),
        ("long_sleeved_outwear", "jacket"),
        ("jumper", "jacket"),
        ("Jeans", "pants"),
        ("shoesClassic", "shoes"),
        ("shoesSports", "shoes"),
        ("SANDALS", "shoes"),
        ("Áo thun", "tshirt"),
        ("handbag", None),
    ],
)
def test_class_name_normalization(raw_name: str, expected: str | None) -> None:
    assert main.normalize_class_name(raw_name) == expected
