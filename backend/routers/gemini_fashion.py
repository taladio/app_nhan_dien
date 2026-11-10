"""Gemini suggestions and follow-up chat using existing YOLO metadata."""

from __future__ import annotations

from collections.abc import Callable

from fastapi import APIRouter, HTTPException
from fastapi.concurrency import run_in_threadpool

try:
    from ..schemas.gemini_fashion import (
        GeminiChatReply, GeminiChatRequest, GeminiSuggestion,
        GeminiSuggestionRequest,
    )
    from ..services.gemini_fashion_service import GeminiFashionService, GeminiServiceError
except ImportError:  # pragma: no cover - supports running from backend/
    from schemas.gemini_fashion import (
        GeminiChatReply, GeminiChatRequest, GeminiSuggestion,
        GeminiSuggestionRequest,
    )
    from services.gemini_fashion_service import GeminiFashionService, GeminiServiceError


def create_gemini_fashion_router(
    service_factory: Callable[[], GeminiFashionService] | None = None,
) -> APIRouter:
    router = APIRouter(prefix="/api/v1/outfit", tags=["gemini-fashion"])
    factory = service_factory or GeminiFashionService.from_environment

    @router.post("/suggest", response_model=GeminiSuggestion)
    async def suggest(request: GeminiSuggestionRequest) -> GeminiSuggestion:
        try:
            service = factory()
            try:
                return await run_in_threadpool(service.suggest, request)
            finally:
                service.close()
        except GeminiServiceError as error:
            raise HTTPException(status_code=error.status_code, detail=error.message) from error

    @router.post("/chat", response_model=GeminiChatReply)
    async def chat(request: GeminiChatRequest) -> GeminiChatReply:
        try:
            service = factory()
            try:
                return await run_in_threadpool(service.chat, request)
            finally:
                service.close()
        except GeminiServiceError as error:
            raise HTTPException(status_code=error.status_code, detail=error.message) from error

    return router
