"""Endpoint kết hợp YOLO và đánh giá phối đồ OpenAI/fallback."""

from __future__ import annotations

import logging
from typing import Any, Callable

import numpy as np
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool

try:
    from ..schemas.outfit_analysis import (
        AnalysisContext,
        AnalysisPayload,
        DetectedItem,
        Occasion,
        OutfitAnalysisResponse,
        Season,
        Style,
        UserProfile,
        finalize_evaluation,
    )
    from ..services.openai_outfit_service import OpenAIOutfitService
    from ..services.rule_based_outfit_service import evaluate_with_rules
except ImportError:  # Hỗ trợ `cd backend; uvicorn main:app`.
    from schemas.outfit_analysis import (
        AnalysisContext,
        AnalysisPayload,
        DetectedItem,
        Occasion,
        OutfitAnalysisResponse,
        Season,
        Style,
        UserProfile,
        finalize_evaluation,
    )
    from services.openai_outfit_service import OpenAIOutfitService
    from services.rule_based_outfit_service import evaluate_with_rules

LOGGER = logging.getLogger(__name__)
NO_DETECTION_MESSAGE = (
    "Không nhận diện được trang phục trong ảnh. Hãy thử ảnh rõ hơn và chụp toàn thân."
)


def _to_detected_item(item: dict[str, Any]) -> DetectedItem:
    return DetectedItem(
        detection_id=item["detection_id"],
        class_id=item["class_id"],
        raw_class_name=item["raw_class_name"],
        class_name=item["class_name"],
        class_name_vi=item["class_name_vi"],
        primary_color=item["primary_color"],
        secondary_colors=item["secondary_colors"],
        confidence=item["confidence"],
        bbox=item["bbox"],
    )


def create_outfit_analysis_router(
    *,
    runtime: Any,
    run_yolo: Callable[[np.ndarray, float, float], Any],
    process_yolo_results: Callable[
        [Any, np.ndarray, dict[int, str]], tuple[list[dict[str, Any]], int]
    ],
    validate_and_decode_image: Callable[[bytes, str | None], np.ndarray],
    safe_filename: Callable[[str | None], str],
    max_image_size: int,
) -> APIRouter:
    router = APIRouter(prefix="/api/v1/outfit", tags=["outfit-analysis"])

    @router.post("/analyze", response_model=OutfitAnalysisResponse)
    async def analyze_outfit(
        file: UploadFile = File(..., description="Ảnh JPEG hoặc PNG, tối đa 10 MB"),
        height_cm: float = Form(..., gt=0, le=300),
        weight_kg: float = Form(..., gt=0, le=500),
        season: Season = Form(...),
        temperature_c: float = Form(..., ge=-100, le=100),
        style: Style = Form(...),
        occasion: Occasion = Form(...),
        confidence: float = Form(0.25, ge=0, le=1),
    ) -> OutfitAnalysisResponse:
        content_type = (file.content_type or "").split(";", maxsplit=1)[0].lower()
        if content_type not in {"image/jpeg", "image/jpg", "image/png"}:
            await file.close()
            raise HTTPException(status_code=400, detail="Chỉ chấp nhận ảnh JPG, JPEG hoặc PNG.")

        try:
            data = await file.read(max_image_size + 1)
        finally:
            await file.close()
        image = validate_and_decode_image(data, content_type)

        if not runtime.loaded:
            raise HTTPException(
                status_code=503,
                detail="Mô hình chưa sẵn sàng. Hãy đặt best.pt tại backend/models/best.pt.",
            )

        try:
            results = await run_in_threadpool(run_yolo, image, confidence, 0.45)
            detections, _ = process_yolo_results(results, image, runtime.names)
        except Exception:
            LOGGER.exception("Lỗi khi chạy YOLO cho outfit analysis")
            raise HTTPException(
                status_code=500,
                detail="Không thể xử lý ảnh bằng mô hình nhận diện.",
            ) from None

        if not detections:
            raise HTTPException(status_code=422, detail=NO_DETECTION_MESSAGE)

        items = [_to_detected_item(item) for item in detections]
        payload = AnalysisPayload(
            detected_items=items,
            user_profile=UserProfile(height_cm=height_cm, weight_kg=weight_kg),
            context=AnalysisContext(
                season=season,
                temperature_c=temperature_c,
                style=style,
                occasion=occasion,
            ),
        )

        source = "openai"
        try:
            service = OpenAIOutfitService.from_environment()
            model_evaluation = await run_in_threadpool(service.evaluate, payload)
        except Exception as error:
            # Chỉ log loại lỗi, không log request/header/API key hoặc nội dung người dùng.
            LOGGER.warning("OpenAI không khả dụng; dùng fallback (%s)", type(error).__name__)
            source = "fallback"
            model_evaluation = await run_in_threadpool(evaluate_with_rules, payload)

        image_height, image_width = image.shape[:2]
        return OutfitAnalysisResponse(
            filename=safe_filename(file.filename),
            image_width=image_width,
            image_height=image_height,
            source=source,
            detected_items=items,
            evaluation=finalize_evaluation(model_evaluation),
        )

    return router
