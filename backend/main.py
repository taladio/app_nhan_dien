"""FastAPI backend nhận diện tám nhóm quần áo bằng Ultralytics YOLO."""

from __future__ import annotations

import logging
import math
import os
import re
import threading
import unicodedata
from collections import Counter
from io import BytesIO
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError

try:
    from .services.color_detector import detect_clothing_colors
    from .routers.try_on import router as try_on_router
except ImportError:  # Hỗ trợ `cd backend; uvicorn main:app`.
    from services.color_detector import detect_clothing_colors
    from routers.try_on import router as try_on_router

BACKEND_DIR = Path(__file__).resolve().parent
PIL_IMAGE_OPEN = Image.open

# Giữ cấu hình Ultralytics trong thư mục backend để server vẫn khởi động khi
# thư mục AppData của tài khoản Windows không cho phép đọc/ghi. Ultralytics tự
# nối thêm thư mục con "Ultralytics" vào đường dẫn này.
os.environ.setdefault("YOLO_CONFIG_DIR", str(BACKEND_DIR))

try:
    import torch
except Exception:  # pragma: no cover - chỉ xảy ra khi môi trường cài đặt bị lỗi
    torch = None  # type: ignore[assignment]

try:
    from ultralytics import YOLO
except Exception:  # pragma: no cover - được phản ánh qua /health
    YOLO = None  # type: ignore[assignment,misc]


LOGGER = logging.getLogger(__name__)
DEFAULT_MODEL_PATH = BACKEND_DIR / "models" / "best.pt"
MAX_IMAGE_SIZE = 10 * 1024 * 1024

APP_CLASSES: dict[str, str] = {
    "tshirt": "Áo thun",
    "shirt": "Áo sơ mi",
    "jacket": "Áo khoác",
    "pants": "Quần dài",
    "shorts": "Quần short",
    "skirt": "Chân váy",
    "dress": "Váy liền thân",
    "shoes": "Giày",
}


def _compact_name(value: str) -> str:
    """Chuẩn hóa tên lớp theo yêu cầu: chữ thường và bỏ khoảng/gạch nối."""

    return re.sub(r"[\s_-]+", "", value.strip().lower())


def _remove_vietnamese_accents(value: str) -> str:
    normalized = unicodedata.normalize("NFD", value)
    return "".join(char for char in normalized if unicodedata.category(char) != "Mn").replace(
        "đ", "d"
    )


# Các biến thể DeepFashion/YOLO thường gặp cũng được gộp về tám nhóm của ứng dụng.
_CLASS_ALIASES: dict[str, str] = {
    # Áo thun / top
    "tshirt": "tshirt",
    "tshirts": "tshirt",
    "tee": "tshirt",
    "tees": "tshirt",
    "top": "tshirt",
    "tops": "tshirt",
    "shortsleevetop": "tshirt",
    "shortsleevedtop": "tshirt",
    "shortsleevetshirt": "tshirt",
    "shortsleevedtshirt": "tshirt",
    "aothun": "tshirt",
    "aophong": "tshirt",
    # Áo sơ mi / blouse
    "shirt": "shirt",
    "shirts": "shirt",
    "blouse": "shirt",
    "blouses": "shirt",
    "longsleeveshirt": "shirt",
    "longsleevedshirt": "shirt",
    "shortsleeveshirt": "shirt",
    "shortsleevedshirt": "shirt",
    "aosomi": "shirt",
    # Áo khoác / áo ngoài
    "jacket": "jacket",
    "jackets": "jacket",
    "coat": "jacket",
    "coats": "jacket",
    "hoodie": "jacket",
    "hoodies": "jacket",
    "jumper": "jacket",
    "jumpers": "jacket",
    "outwear": "jacket",
    "outerwear": "jacket",
    "shortsleeveoutwear": "jacket",
    "shortsleevedoutwear": "jacket",
    "longsleeveoutwear": "jacket",
    "longsleevedoutwear": "jacket",
    "aokhoac": "jacket",
    # Quần dài
    "pants": "pants",
    "pant": "pants",
    "trouser": "pants",
    "trousers": "pants",
    "jean": "pants",
    "jeans": "pants",
    "quandai": "pants",
    "quanjean": "pants",
    "quantay": "pants",
    # Quần short
    "short": "shorts",
    "shorts": "shorts",
    "quanshort": "shorts",
    "quanngan": "shorts",
    # Chân váy
    "skirt": "skirt",
    "skirts": "skirt",
    "chanvay": "skirt",
    # Váy liền thân
    "dress": "dress",
    "dresses": "dress",
    "shortsleevedress": "dress",
    "shortsleeveddress": "dress",
    "longsleevedress": "dress",
    "longsleeveddress": "dress",
    "vestdress": "dress",
    "slingdress": "dress",
    "vaylienthan": "dress",
    "dam": "dress",
    # Giày dép
    "shoe": "shoes",
    "shoes": "shoes",
    "shoesclassic": "shoes",
    "shoessports": "shoes",
    "sneaker": "shoes",
    "sneakers": "shoes",
    "footwear": "shoes",
    "sandal": "shoes",
    "sandals": "shoes",
    "boot": "shoes",
    "boots": "shoes",
    "giay": "shoes",
    "dep": "shoes",
}


def normalize_class_name(raw_name: str) -> str | None:
    """Trả về một trong tám lớp ứng dụng, hoặc ``None`` để bỏ qua lớp khác."""

    compact = _compact_name(raw_name)
    mapped = _CLASS_ALIASES.get(compact)
    if mapped is not None:
        return mapped

    # Hỗ trợ model đặt tên lớp bằng tiếng Việt có/không dấu.
    ascii_compact = _remove_vietnamese_accents(compact)
    return _CLASS_ALIASES.get(ascii_compact)


def _configured_model_path() -> tuple[Path, str]:
    override = os.getenv("MODEL_PATH", "").strip()
    if not override:
        return DEFAULT_MODEL_PATH, "models/best.pt"

    path = Path(override).expanduser()
    if not path.is_absolute():
        path = (Path.cwd() / path).resolve()
    return path, Path(override).as_posix()


def _choose_device() -> str:
    if torch is not None and torch.cuda.is_available():
        return "cuda:0"
    return "cpu"


def _coerce_model_names(names: Any) -> dict[int, str]:
    if isinstance(names, dict):
        return {int(class_id): str(name) for class_id, name in names.items()}
    if isinstance(names, (list, tuple)):
        return {class_id: str(name) for class_id, name in enumerate(names)}
    return {}


class ModelRuntime:
    """Giữ model dùng chung và bảo đảm model chỉ được thử tải đúng một lần."""

    def __init__(self, model_path: Path, model_path_label: str) -> None:
        self.model_path = model_path
        self.model_path_label = model_path_label
        self.device = _choose_device()
        self.model: Any | None = None
        self.names: dict[int, str] = {}
        self.load_error: str | None = None
        self._load_attempted = False
        self._load_lock = threading.Lock()
        self.inference_lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self.model is not None

    def load_once(self) -> None:
        with self._load_lock:
            if self._load_attempted:
                return
            self._load_attempted = True

            if not self.model_path.is_file():
                self.load_error = (
                    "Không tìm thấy mô hình. Hãy đặt best.pt tại backend/models/best.pt."
                )
                return

            if YOLO is None:
                self.load_error = (
                    "Không thể nhập Ultralytics YOLO. Hãy cài các thư viện trong requirements.txt."
                )
                return

            try:
                loaded_model = YOLO(str(self.model_path))
                model_names = _coerce_model_names(getattr(loaded_model, "names", None))
                if not model_names:
                    raise ValueError("model.names không có lớp hợp lệ")
                self.model = loaded_model
                self.names = model_names
            except Exception:
                LOGGER.exception("Không thể tải mô hình YOLO")
                self.load_error = "Không thể tải mô hình YOLO từ tệp đã cấu hình."


MODEL_PATH, MODEL_PATH_LABEL = _configured_model_path()
runtime = ModelRuntime(MODEL_PATH, MODEL_PATH_LABEL)
runtime.load_once()


app = FastAPI(
    title="Fashion AI API",
    description="API nhận diện và đánh giá trang phục cho ứng dụng Flutter.",
    version="2.0.0",
)

# CORS mở trong giai đoạn phát triển để Flutter Web và các Flutter client gọi API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root() -> dict[str, str]:
    return {
        "message": "Fashion AI API đang hoạt động",
        "documentation": "/docs",
    }


@app.get("/health")
def health() -> dict[str, Any]:
    payload: dict[str, Any] = {
        "status": "ok" if runtime.loaded else "degraded",
        "model_loaded": runtime.loaded,
        "model_path": runtime.model_path_label,
        "device": runtime.device,
        "number_of_model_classes": len(runtime.names),
    }
    if runtime.load_error:
        payload["model_error"] = runtime.load_error
    payload.update(
        {
            "pose_model_loaded": pose_runtime.loaded,
            "pose_model_path": str(pose_runtime.model_path),
        }
    )
    if pose_runtime.load_error:
        payload["pose_model_error"] = pose_runtime.load_error
    return payload


@app.get("/api/v1/classes")
def classes() -> dict[str, Any]:
    model_classes = []
    for class_id, raw_name in sorted(runtime.names.items()):
        normalized = normalize_class_name(raw_name)
        model_classes.append(
            {
                "class_id": class_id,
                "raw_class_name": raw_name,
                "class_name": normalized,
                "class_name_vi": APP_CLASSES.get(normalized) if normalized else None,
            }
        )

    return {
        "model_loaded": runtime.loaded,
        "model_classes": model_classes,
        "application_classes": [
            {"class_name": name, "class_name_vi": vietnamese_name}
            for name, vietnamese_name in APP_CLASSES.items()
        ],
    }


_MIME_TO_FORMATS = {
    "image/jpeg": {"JPEG"},
    "image/jpg": {"JPEG"},
    "image/png": {"PNG"},
    "image/webp": {"WEBP"},
}


def validate_and_decode_image(data: bytes, content_type: str | None) -> np.ndarray:
    """Kiểm tra MIME lẫn nội dung thật rồi giải mã ảnh thành ma trận BGR."""

    if not data:
        raise HTTPException(status_code=400, detail="Tệp ảnh không được để trống.")
    if len(data) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=400, detail="Tệp ảnh vượt quá giới hạn 10 MB.")

    mime_type = (content_type or "").split(";", maxsplit=1)[0].strip().lower()
    if not mime_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="MIME type của tệp phải là ảnh.")
    if mime_type not in _MIME_TO_FORMATS:
        raise HTTPException(
            status_code=400,
            detail="Chỉ chấp nhận ảnh JPEG, PNG hoặc WebP.",
        )

    try:
        # Dùng hàm gốc của Pillow vì Ultralytics thay Image.open bằng wrapper
        # tự cài pi-heif, khiến ảnh hỏng biến thành lỗi phụ thuộc thay vì HTTP 400.
        with PIL_IMAGE_OPEN(BytesIO(data)) as image_probe:
            detected_format = (image_probe.format or "").upper()
            image_probe.verify()
    except (UnidentifiedImageError, OSError, ValueError):
        raise HTTPException(
            status_code=400,
            detail="Nội dung tệp không phải là ảnh hợp lệ hoặc đã bị hỏng.",
        ) from None

    if detected_format not in {"JPEG", "PNG", "WEBP"}:
        raise HTTPException(status_code=400, detail="Chỉ chấp nhận ảnh JPEG, PNG hoặc WebP.")
    if detected_format not in _MIME_TO_FORMATS[mime_type]:
        raise HTTPException(
            status_code=400,
            detail="MIME type không khớp với định dạng ảnh thực tế.",
        )

    encoded = np.frombuffer(data, dtype=np.uint8)
    image = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
    if image is None or image.ndim != 3 or image.shape[0] <= 0 or image.shape[1] <= 0:
        raise HTTPException(status_code=400, detail="Không thể giải mã nội dung ảnh.")
    return image


def detect_dominant_color(crop: np.ndarray) -> str:
    """Giữ API màu cũ; endpoint mới còn nhận tối đa hai màu phụ."""

    return detect_clothing_colors(crop)[0]


def _to_numpy(value: Any) -> np.ndarray:
    if hasattr(value, "detach"):
        value = value.detach()
    if hasattr(value, "cpu"):
        value = value.cpu()
    if hasattr(value, "numpy"):
        value = value.numpy()
    return np.asarray(value)


def _clamp_bbox(raw_bbox: Any, image_width: int, image_height: int) -> dict[str, int] | None:
    coords = np.asarray(raw_bbox, dtype=float).reshape(-1)
    if coords.size < 4 or not np.isfinite(coords[:4]).all():
        return None

    x1_float = min(max(float(coords[0]), 0.0), float(image_width))
    y1_float = min(max(float(coords[1]), 0.0), float(image_height))
    x2_float = min(max(float(coords[2]), 0.0), float(image_width))
    y2_float = min(max(float(coords[3]), 0.0), float(image_height))

    x1 = min(max(int(round(x1_float)), 0), image_width)
    y1 = min(max(int(round(y1_float)), 0), image_height)
    x2 = min(max(int(round(x2_float)), 0), image_width)
    y2 = min(max(int(round(y2_float)), 0), image_height)
    if x2 <= x1 or y2 <= y1:
        return None
    return {"x1": x1, "y1": y1, "x2": x2, "y2": y2}


def process_yolo_results(
    results: Any,
    image: np.ndarray,
    model_names: dict[int, str],
) -> tuple[list[dict[str, Any]], int]:
    """Chuyển boxes.xyxy/conf/cls thành JSON và lọc ngoài tám lớp."""

    result_items = list(results) if results is not None else []
    if not result_items:
        return [], 0

    boxes = getattr(result_items[0], "boxes", None)
    if boxes is None:
        return [], 0

    xyxy = _to_numpy(getattr(boxes, "xyxy", [])).astype(float, copy=False)
    confidences = _to_numpy(getattr(boxes, "conf", [])).astype(float, copy=False).reshape(-1)
    class_ids = _to_numpy(getattr(boxes, "cls", [])).astype(float, copy=False).reshape(-1)

    if xyxy.size == 0:
        return [], 0
    if xyxy.ndim == 1:
        xyxy = xyxy.reshape(1, -1)

    image_height, image_width = image.shape[:2]
    detections: list[dict[str, Any]] = []
    ignored_count = 0

    for index in range(xyxy.shape[0]):
        if index >= confidences.size or index >= class_ids.size:
            ignored_count += 1
            continue

        confidence = float(confidences[index])
        class_id_value = float(class_ids[index])
        if not math.isfinite(confidence) or not math.isfinite(class_id_value):
            ignored_count += 1
            continue

        class_id = int(class_id_value)
        raw_class_name = model_names.get(class_id)
        normalized_name = normalize_class_name(raw_class_name) if raw_class_name else None
        if normalized_name is None:
            ignored_count += 1
            continue

        bbox = _clamp_bbox(xyxy[index], image_width, image_height)
        if bbox is None:
            ignored_count += 1
            continue

        crop = image[bbox["y1"] : bbox["y2"], bbox["x1"] : bbox["x2"]]
        primary_color, secondary_colors = detect_clothing_colors(crop)
        detections.append(
            {
                "class_id": class_id,
                "raw_class_name": raw_class_name,
                "class_name": normalized_name,
                "class_name_vi": APP_CLASSES[normalized_name],
                # `color` được giữ để không phá response của /api/v1/detect.
                "color": primary_color,
                "primary_color": primary_color,
                "secondary_colors": secondary_colors,
                "confidence": round(min(max(confidence, 0.0), 1.0), 4),
                "bbox": bbox,
                "bbox_normalized": {
                    "x1": round(bbox["x1"] / image_width, 4),
                    "y1": round(bbox["y1"] / image_height, 4),
                    "x2": round(bbox["x2"] / image_width, 4),
                    "y2": round(bbox["y2"] / image_height, 4),
                },
            }
        )

    detections.sort(key=lambda item: item["confidence"], reverse=True)
    for index, detection in enumerate(detections, start=1):
        detection["detection_id"] = f"det_{index}"
    return detections, ignored_count


def _run_yolo(image: np.ndarray, confidence: float, iou: float) -> Any:
    if not runtime.loaded:
        raise RuntimeError("model_unavailable")

    # Ultralytics/PyTorch dùng state chung; khóa tránh hai request suy luận đồng thời.
    with runtime.inference_lock:
        return runtime.model.predict(
            source=image,
            imgsz=640,
            conf=confidence,
            iou=iou,
            verbose=False,
            device=runtime.device,
        )


def _safe_filename(filename: str | None) -> str:
    if not filename:
        return "upload"
    return filename.replace("\\", "/").rsplit("/", maxsplit=1)[-1] or "upload"


@app.post("/api/v1/detect")
async def detect(
    file: UploadFile = File(..., description="Ảnh JPEG, PNG hoặc WebP, tối đa 10 MB"),
    confidence: float = Query(0.25, ge=0.0, le=1.0),
    iou: float = Query(0.45, ge=0.0, le=1.0),
) -> dict[str, Any]:
    try:
        data = await file.read(MAX_IMAGE_SIZE + 1)
    finally:
        await file.close()

    image = validate_and_decode_image(data, file.content_type)
    if not runtime.loaded:
        raise HTTPException(
            status_code=503,
            detail="Mô hình chưa sẵn sàng. Hãy đặt best.pt tại backend/models/best.pt.",
        )

    try:
        results = await run_in_threadpool(_run_yolo, image, confidence, iou)
        detections, ignored_count = process_yolo_results(results, image, runtime.names)
    except Exception:
        LOGGER.exception("Lỗi khi chạy suy luận YOLO")
        raise HTTPException(
            status_code=500,
            detail="Không thể xử lý ảnh bằng mô hình nhận diện.",
        ) from None

    summary_counts = Counter(item["class_name"] for item in detections)
    summary = [
        {
            "class_name": class_name,
            "class_name_vi": APP_CLASSES[class_name],
            "count": summary_counts[class_name],
        }
        for class_name in APP_CLASSES
        if summary_counts[class_name] > 0
    ]

    image_height, image_width = image.shape[:2]
    return {
        "filename": _safe_filename(file.filename),
        "image_width": image_width,
        "image_height": image_height,
        "detection_count": len(detections),
        "ignored_detection_count": ignored_count,
        "detections": detections,
        "summary": summary,
    }


try:
    from .routers.outfit_analysis import create_outfit_analysis_router
    from .routers.pose_websocket import create_pose_websocket_router
    from .routers.weather import router as weather_router
    from .routers.gemini_fashion import create_gemini_fashion_router
    from .services.pose_landmarker_service import pose_runtime
except ImportError:  # Hỗ trợ `cd backend; uvicorn main:app`.
    from routers.outfit_analysis import create_outfit_analysis_router
    from routers.pose_websocket import create_pose_websocket_router
    from routers.weather import router as weather_router
    from routers.gemini_fashion import create_gemini_fashion_router
    from services.pose_landmarker_service import pose_runtime

app.include_router(create_pose_websocket_router())
app.include_router(weather_router)
app.include_router(try_on_router)
app.include_router(create_gemini_fashion_router())

app.include_router(
    create_outfit_analysis_router(
        runtime=runtime,
        run_yolo=_run_yolo,
        process_yolo_results=process_yolo_results,
        validate_and_decode_image=validate_and_decode_image,
        safe_filename=_safe_filename,
        max_image_size=MAX_IMAGE_SIZE,
    )
)
