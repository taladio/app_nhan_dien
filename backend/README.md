# Backend Fashion AI (FastAPI + YOLO)

Backend nhận ảnh từ Flutter, chạy `best.pt` bằng Ultralytics YOLO và chỉ trả về tám
nhóm của ứng dụng: `tshirt`, `shirt`, `jacket`, `pants`, `shorts`, `skirt`,
`dress`, `shoes`.

## 1. Yêu cầu

- Windows và Python **3.10 hoặc 3.11** (khuyến nghị Python 3.11).
- File model thật tại `backend/models/best.pt`.
- Máy có NVIDIA GPU sẽ tự dùng CUDA nếu bản PyTorch đang cài nhận được GPU;
  nếu không backend tự dùng CPU.

Backend vẫn khởi động nếu thiếu hoặc không tải được model. Khi đó `/health` có
`status: "degraded"`, `model_loaded: false`; endpoint nhận diện trả HTTP 503.

## 2. Tạo môi trường và cài thư viện

Chạy từ thư mục gốc `app_nhan_dien`.

### Windows PowerShell

```powershell
py -3.11 -m venv backend\.venv
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\backend\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt
```

### Windows CMD

```bat
py -3.11 -m venv backend\.venv
backend\.venv\Scripts\activate.bat
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt
```

Nếu lệnh `py` không tồn tại nhưng `python --version` đúng 3.10/3.11, thay
`py -3.11` bằng `python`.

## 3. Đặt model

Sao chép đúng file model đã huấn luyện vào:

```text
backend/models/best.pt
```

Không đổi nội dung hoặc tạo file `.pt` giả. Đường dẫn mặc định được tính từ
`backend/main.py`, nên không phụ thuộc thư mục đứng khi chạy Uvicorn.

Nếu cần dùng model ở vị trí khác, có thể đặt biến môi trường trước khi chạy:

```powershell
$env:MODEL_PATH = "backend\models\best.pt"
```

Đường dẫn tương đối trong `MODEL_PATH` được tính từ thư mục hiện tại của terminal.

## 4. Chạy server

Từ thư mục gốc project:

```powershell
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

Hoặc từ thư mục `backend`:

```powershell
cd backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

`0.0.0.0` cho phép Android Emulator và thiết bị trong cùng mạng gọi tới máy tính.
Không dùng `0.0.0.0` làm URL phía Flutter; dùng một trong các URL bên dưới.

## 5. Kiểm tra API

Mở trên máy tính:

- Trạng thái: <http://127.0.0.1:8000/health>
- Swagger UI: <http://127.0.0.1:8000/docs>
- Danh sách lớp: <http://127.0.0.1:8000/api/v1/classes>

Trong Swagger, mở `POST /api/v1/detect`, chọn **Try it out**, đặt
`confidence`/`iou`, chọn ảnh ở trường `file`, rồi bấm **Execute**.

Ví dụ với `curl.exe` trên Windows PowerShell hoặc CMD:

```powershell
curl.exe -X POST "http://127.0.0.1:8000/api/v1/detect?confidence=0.25&iou=0.45" -H "accept: application/json" -F "file=@C:\duong-dan\outfit.jpg;type=image/jpeg"
```

Ảnh hợp lệ là JPEG, PNG hoặc WebP, tối đa 10 MB. Tên trường multipart bắt buộc là
`file`. Không phát hiện được quần áo vẫn là kết quả HTTP 200 với
`detection_count: 0`.

## 6. URL dùng trong Flutter

```text
Flutter Windows/Web: http://127.0.0.1:8000
Android Emulator:    http://10.0.2.2:8000
Điện thoại thật:     http://IP_MAY_TINH:8000
```

Để tìm `IP_MAY_TINH`, mở CMD hoặc PowerShell và chạy:

```powershell
ipconfig
```

Tìm dòng **IPv4 Address** của card Wi-Fi đang dùng, ví dụ `192.168.1.25`, rồi
dùng `http://192.168.1.25:8000`. Điện thoại và máy tính phải cùng Wi-Fi. Khi
Windows hỏi quyền mạng, cho phép Python/Uvicorn qua **Windows Firewall** trên mạng
Private. Có thể cần tạo inbound rule cho TCP port 8000 nếu firewall vẫn chặn.

## 7. Chạy kiểm thử

Từ thư mục gốc, sau khi kích hoạt `.venv`:

```powershell
python -m compileall backend
python -m pytest backend/tests -v
```

Test dùng model YOLO giả để không phụ thuộc bắt buộc vào `best.pt`. Việc model thật
có tải được hay không cần kiểm tra thêm qua `/health` và `/api/v1/classes`.

## 8. Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| `/health` báo `model_loaded: false` | Kiểm tra đúng `backend/models/best.pt`, kích thước file và đã cài `ultralytics`, `torch`. |
| `/api/v1/detect` trả 503 | Model đang thiếu hoặc tải thất bại; xem `/health` và log terminal. |
| Trả 400 về ảnh | Chỉ gửi JPEG/PNG/WebP thật, MIME đúng định dạng và nhỏ hơn hoặc bằng 10 MB. |
| Flutter Web báo CORS/network | Kiểm tra server đang chạy, URL đúng; backend đã mở CORS cho môi trường phát triển. |
| Android Emulator không kết nối | Dùng `10.0.2.2`, không dùng `127.0.0.1`. |
| Điện thoại thật không kết nối | Chạy Uvicorn với `--host 0.0.0.0`, cùng Wi-Fi, dùng IPv4 máy tính và kiểm tra firewall. |
| GPU không được dùng | Kiểm tra `torch.cuda.is_available()` và cài đúng PyTorch/CUDA; backend vẫn chạy CPU. |
| Port 8000 đã được dùng | Dừng tiến trình cũ hoặc đổi `--port`, đồng thời cập nhật URL trong Flutter. |
