"""One-shot garment cutout; never called for camera frames."""

import asyncio

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import Response

try:
    from ..services.garment_cutout_service import MAX_UPLOAD_BYTES, CutoutError, cutout_garment
except ImportError:
    from services.garment_cutout_service import MAX_UPLOAD_BYTES, CutoutError, cutout_garment

router = APIRouter(prefix="/api/v1/try-on", tags=["try-on"])
_slots = asyncio.Semaphore(1)


@router.post("/cutout")
async def garment_cutout(
    file: UploadFile = File(...),
    x: float = Form(0, ge=0, le=1),
    y: float = Form(0, ge=0, le=1),
    width: float = Form(1, gt=0, le=1),
    height: float = Form(1, gt=0, le=1),
) -> Response:
    try:
        if file.content_type not in {"image/jpeg", "image/png", "image/webp"}:
            raise HTTPException(415, "Chỉ hỗ trợ ảnh JPEG, PNG hoặc WebP.")
        data = await file.read(MAX_UPLOAD_BYTES + 1)
    finally:
        await file.close()
    if not data:
        raise HTTPException(400, "Ảnh không có dữ liệu.")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(413, "Ảnh tối đa 10 MB.")
    try:
        await asyncio.wait_for(_slots.acquire(), timeout=1)
    except TimeoutError:
        raise HTTPException(503, "Đang tách nền ảnh khác. Hãy thử lại sau.") from None
    try:
        png = await run_in_threadpool(cutout_garment, data, (x, y, width, height))
    except CutoutError as error:
        raise HTTPException(422, str(error)) from None
    finally:
        _slots.release()
    return Response(png, media_type="image/png", headers={"Cache-Control": "no-store"})
