"""WebSocket nhận JPEG camera và trả landmark cơ thể."""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any, Protocol

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from pydantic import ValidationError

try:
    from ..schemas.pose_result import PoseConfig, PoseResult
    from ..services.pose_landmarker_service import (
        InvalidPoseFrame,
        PoseAnalysis,
        pose_runtime,
    )
except ImportError:  # Hỗ trợ `cd backend; uvicorn main:app`.
    from schemas.pose_result import PoseConfig, PoseResult
    from services.pose_landmarker_service import (
        InvalidPoseFrame,
        PoseAnalysis,
        pose_runtime,
    )


LOGGER = logging.getLogger(__name__)
FULL_BODY_MESSAGE = "Hãy đứng lùi lại để camera nhìn thấy toàn thân."


class PoseProcessor(Protocol):
    loaded: bool
    load_error: str | None

    def load_once(self) -> None: ...

    def process_jpeg(self, data: bytes, timestamp_ms: int) -> PoseAnalysis | None: ...


def _error(message: str) -> dict[str, str]:
    return {"type": "error", "message": message}


def create_pose_websocket_router(
    processor: PoseProcessor = pose_runtime,
) -> APIRouter:
    router = APIRouter(prefix="/api/v1/pose", tags=["pose"])

    @router.websocket("/ws")
    async def pose_websocket(websocket: WebSocket) -> None:
        await websocket.accept()
        try:
            try:
                first_message = await asyncio.wait_for(websocket.receive(), timeout=10)
                if first_message.get("text") is None:
                    await websocket.send_json(
                        _error("Thông điệp đầu tiên phải là cấu hình camera."),
                    )
                    await websocket.close(code=1003)
                    return
                PoseConfig.model_validate_json(first_message["text"])
            except (ValidationError, ValueError):
                await websocket.send_json(_error("Cấu hình camera không hợp lệ."))
                await websocket.close(code=1003)
                return
            except TimeoutError:
                await websocket.send_json(_error("Quá thời gian chờ cấu hình camera."))
                await websocket.close(code=1008)
                return

            processor.load_once()
            if not processor.loaded:
                await websocket.send_json(
                    _error(processor.load_error or "Pose Landmarker chưa sẵn sàng."),
                )
                await websocket.close(code=1011)
                return

            frame_id = 0
            while True:
                message = await websocket.receive()
                if message["type"] == "websocket.disconnect":
                    break
                frame = message.get("bytes")
                if frame is None:
                    await websocket.send_json(
                        _error("Sau cấu hình, frame phải là JPEG dạng binary."),
                    )
                    continue

                frame_id += 1
                timestamp_ms = int(time.time() * 1000)
                started = time.perf_counter()
                try:
                    analysis = await run_in_threadpool(
                        processor.process_jpeg,
                        frame,
                        timestamp_ms,
                    )
                except InvalidPoseFrame:
                    await websocket.send_json(_error("Khung hình JPEG không hợp lệ."))
                    continue
                except Exception:
                    LOGGER.exception("Lỗi xử lý pose frame %s", frame_id)
                    await websocket.send_json(
                        _error("Không thể xử lý khung hình bằng MediaPipe Pose."),
                    )
                    continue
                finally:
                    frame = None

                processing_ms = (time.perf_counter() - started) * 1000
                if analysis is None:
                    result = PoseResult(
                        frame_id=frame_id,
                        timestamp_ms=timestamp_ms,
                        processing_ms=processing_ms,
                        pose_detected=False,
                        body_visible=False,
                        message=FULL_BODY_MESSAGE,
                    )
                else:
                    result = PoseResult(
                        frame_id=frame_id,
                        timestamp_ms=timestamp_ms,
                        processing_ms=processing_ms,
                        pose_detected=True,
                        body_visible=(
                            analysis.anchors.body_visible if analysis.anchors else False
                        ),
                        landmarks=analysis.landmarks,
                        world_landmarks=analysis.world_landmarks,
                        anchors=analysis.anchors,
                    )
                await websocket.send_json(
                    result.model_dump(mode="json", exclude_none=True),
                )
        except WebSocketDisconnect:
            return
        except RuntimeError:
            # Starlette có thể báo RuntimeError nếu client đóng giữa lúc gửi.
            return

    return router
