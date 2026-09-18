"""Đánh giá trang phục từ metadata YOLO qua OpenAI Responses API."""

from __future__ import annotations

import json
import os
from pathlib import Path

from dotenv import load_dotenv
from openai import OpenAI

try:
    from ..schemas.outfit_analysis import AnalysisPayload, ModelOutfitEvaluation
except ImportError:  # Hỗ trợ chạy backend như một thư mục độc lập.
    from schemas.outfit_analysis import AnalysisPayload, ModelOutfitEvaluation

BACKEND_DIR = Path(__file__).resolve().parents[1]
load_dotenv(BACKEND_DIR / ".env", override=False)

SYSTEM_PROMPT = """
Bạn là trợ lý phối đồ an toàn và thực tế. Chỉ đánh giá metadata trang phục đã
nhận diện, không được suy đoán từ ảnh. Hãy chấm năm điểm 0-100 về: màu sắc;
mùa và nhiệt độ; tỷ lệ trang phục chung; phong cách; hoàn cảnh. Nêu điểm mạnh,
điểm cần điều chỉnh, khuyến nghị và một bộ đồ phù hợp hơn.

Quy tắc bắt buộc:
- Không chẩn đoán sức khỏe, không miệt thị ngoại hình và không kết luận béo,
  gầy, xấu hay đẹp.
- Chiều cao/cân nặng chỉ dùng cho gợi ý chung về tỷ lệ, độ dài và cảm giác cân
  đối; không khẳng định size chính xác.
- Không suy đoán giới tính, tuổi, dân tộc hoặc thuộc tính nhạy cảm.
- Không khẳng định chất liệu của món đồ đã nhận diện.
- Chỉ trả dữ liệu đúng schema được cung cấp. Không tự tính overall_score hoặc
  rating vì server sẽ tính lại bằng công thức cố định.
""".strip()


class OpenAIConfigurationError(RuntimeError):
    """Thiếu hoặc sai cấu hình OpenAI; router sẽ chuyển sang fallback."""


class OpenAIOutfitService:
    def __init__(self, *, api_key: str, model: str, timeout_seconds: float) -> None:
        self._client = OpenAI(
            api_key=api_key,
            timeout=timeout_seconds,
            max_retries=1,
        )
        self._model = model

    @classmethod
    def from_environment(cls) -> "OpenAIOutfitService":
        api_key = os.getenv("OPENAI_API_KEY", "").strip()
        if not api_key:
            raise OpenAIConfigurationError("OPENAI_API_KEY chưa được cấu hình")

        model = os.getenv("OPENAI_MODEL", "gpt-5.6-luna").strip() or "gpt-5.6-luna"
        try:
            timeout_seconds = float(os.getenv("OPENAI_TIMEOUT_SECONDS", "30"))
        except ValueError as error:
            raise OpenAIConfigurationError("OPENAI_TIMEOUT_SECONDS không hợp lệ") from error
        if not 1 <= timeout_seconds <= 120:
            raise OpenAIConfigurationError("OPENAI_TIMEOUT_SECONDS phải từ 1 đến 120")
        return cls(api_key=api_key, model=model, timeout_seconds=timeout_seconds)

    def evaluate(self, payload: AnalysisPayload) -> ModelOutfitEvaluation:
        """Chỉ gửi metadata, tuyệt đối không gửi bytes/base64/URL của ảnh."""

        metadata = payload.model_dump(mode="json")
        # Bounding box và tên raw không cần cho tư vấn, nên tiếp tục tối thiểu hóa
        # dữ liệu gửi tới nhà cung cấp mô hình.
        for item in metadata["detected_items"]:
            item.pop("bbox", None)
            item.pop("raw_class_name", None)
            item.pop("class_id", None)
            item.pop("detection_id", None)
            item["color"] = item.pop("primary_color")

        response = self._client.responses.parse(
            model=self._model,
            instructions=SYSTEM_PROMPT,
            input=json.dumps(metadata, ensure_ascii=False),
            text_format=ModelOutfitEvaluation,
            store=False,
        )
        parsed = response.output_parsed
        if parsed is None:
            raise RuntimeError("OpenAI không trả Structured Output hợp lệ")
        return parsed
