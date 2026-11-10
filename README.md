# Nhận diện, phân tích và thử đồ ảo realtime

Ứng dụng Flutter cho phép người dùng đăng nhập bằng Firebase Authentication,
chụp/chọn ảnh trang phục và gửi ảnh trực tiếp trong một request tới FastAPI.
Backend chạy YOLO `best.pt`, nhận diện loại đồ, màu và bounding box, sau đó chỉ
gửi **metadata** sang Gemini để đánh giá. Ảnh không được lưu trên backend,
Firestore, Firebase Storage hay `shared_preferences`.

Nếu Gemini chưa được cấu hình hoặc gặp lỗi, backend vẫn trả nhãn YOLO và Flutter
hiển thị lỗi AI để người dùng thử lại; không sinh gợi ý từ quy tắc cục bộ. Luồng
nhận diện YOLO cũ `/api/v1/detect` và camera realtime vẫn được giữ.
Mục **Thử đồ ảo** dùng Camera + WebSocket + MediaPipe Pose để ghép PNG cục bộ
theo vai, hông, đầu gối và bàn chân; luồng này không gọi Gemini hoặc Firebase.

## 1. Chuẩn bị model và backend

Môi trường đã kiểm thử dùng **Python 3.13.7** và `mediapipe 1.0.1`. Đặt file
trọng số YOLO thật đúng tại:

```text
backend/models/best.pt
```

Từ thư mục gốc repository, chạy PowerShell:

```powershell
python -m venv backend\.venv
.\backend\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt
Copy-Item backend\.env.example backend\.env
python backend\scripts\download_pose_model.py
```

Sửa `backend/.env`:

```dotenv
GEMINI_API_KEY=khóa_của_bạn
GEMINI_MODEL=gemini-3.5-flash-lite
GEMINI_TIMEOUT_SECONDS=45
```

- Tạo key tại [Google AI Studio](https://aistudio.google.com/apikey); không đưa
  key vào Flutter hoặc Git. Thiếu key thì YOLO vẫn chạy nhưng không có gợi ý AI.
- API Gemini có hạn mức và chi phí riêng tùy tài khoản; model có thể đổi bằng
  `GEMINI_MODEL` trong `.env` mà không sửa mã nguồn.

Tệp `.env` đã được git-ignore. Khởi chạy backend:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Kiểm tra trên máy tính:

- Health: <http://127.0.0.1:8000/health>
- Swagger: <http://127.0.0.1:8000/docs>
- Danh sách lớp: <http://127.0.0.1:8000/api/v1/classes>
- Thử đồ realtime: `ws://127.0.0.1:8000/api/v1/pose/ws`

Trong `/docs`, mở `POST /api/v1/outfit/analyze`, chọn **Try it out**, nhập form
và chọn JPG/JPEG/PNG tối đa 10 MB để thử API.

## 2. Endpoint phân tích mới

```http
POST /api/v1/outfit/analyze
Content-Type: multipart/form-data
```

Các trường multipart:

| Trường | Ví dụ | Ghi chú |
|---|---:|---|
| `file` | `outfit.jpg` | JPG/JPEG/PNG, không rỗng, tối đa 10 MB |
| `height_cm` | `170` | Lớn hơn 0, tối đa 300 |
| `weight_kg` | `65` | Lớn hơn 0, tối đa 500 |
| `season` | `summer` | Chỉ gửi ở chế độ Thủ công: `spring`, `summer`, `autumn`, `winter`, `rainy` |
| `temperature_c` | `32` | Thủ công: số nhập; thời tiết hiện tại: nhiệt độ Open-Meteo, từ -100 đến 100 |
| `style` | `casual` | Giá trị dropdown của ứng dụng |
| `occasion` | `school` | Giá trị dropdown của ứng dụng |
| `confidence` | `0.25` | Ngưỡng YOLO từ 0 đến 1 |

Response thành công có dạng rút gọn:

```json
{
  "filename": "outfit.jpg",
  "image_width": 1080,
  "image_height": 1920,
  "source": "gemini",
  "ai_error": null,
  "detected_items": [
    {
      "detection_id": "det_1",
      "class_id": 0,
      "raw_class_name": "T-Shirt",
      "class_name": "tshirt",
      "class_name_vi": "Áo thun",
      "primary_color": "Trắng",
      "secondary_colors": [],
      "confidence": 0.91,
      "bbox": {"x1": 220, "y1": 300, "x2": 820, "y2": 950}
    }
  ],
  "evaluation": {
    "overall_score": 82.5,
    "rating": "Phù hợp",
    "color_score": 90,
    "season_temperature_score": 85,
    "body_proportion_score": 75,
    "style_score": 80,
    "occasion_score": 80,
    "summary": "Bộ đồ hài hòa và phù hợp mức nhiệt.",
    "strengths": ["Bảng màu cân bằng."],
    "problems": [],
    "recommendations": ["Giữ một màu trung tính làm nền."],
    "suggested_outfit": {
      "top": "Áo thun trắng",
      "bottom": "Quần short màu be",
      "outerwear": null,
      "shoes": "Giày trắng",
      "reason": "Phù hợp mùa hè và hoàn cảnh đã chọn."
    }
  }
}
```

`overall_score` được backend tính lại, làm tròn một chữ số, theo công thức:

```text
color × 0.30 + season_temperature × 0.30 + body_proportion × 0.20
+ style × 0.10 + occasion × 0.10
```

Nếu YOLO không xác định được màu, `color_score` là `null`; backend bỏ phần trọng
số màu và chuẩn hóa tổng các trọng số còn lại. Điểm số chỉ mang tính tham khảo.

Khi YOLO không thấy trang phục, endpoint trả HTTP 422 với hướng dẫn chụp ảnh rõ
hơn. Khi thiếu `best.pt`, endpoint trả HTTP 503. Nếu Gemini lỗi, endpoint vẫn
trả nhãn YOLO với `source: "unavailable"`, không bịa gợi ý dự phòng.

## 3. Chạy Flutter

Ứng dụng hiện được chạy và kiểm tra trên **điện thoại Android thật**, không dùng
giả lập. Máy tính và điện thoại cần ở cùng Wi-Fi. Địa chỉ backend của app được
đặt tập trung tại `localWifiBaseUrl` trong `lib/config/api_config.dart`.

**Bấm Run trong Android Studio (Windows):** chọn `main.dart`, chọn điện thoại
thật và bấm ▶. Cấu hình đã có bước **Before launch → Start local backend**:
backend đang chạy thì dùng lại; chưa chạy thì tự bật nền và đợi sẵn sàng trước
khi chạy Flutter. Nếu IDE chưa nhận cấu hình vừa sửa, đóng rồi mở lại project.
Plugin **Shell Script** đi kèm Android Studio cần được bật. Log nằm ở
`.dart_tool/backend/server.log`; lỗi khởi động sẽ dừng bước chạy với thông báo.
Backend tiếp tục chạy sau khi dừng app. Khi sửa mã Python, cần dừng backend cũ
và bấm Run lại để nạp mã mới. Bước này không gọi Gemini hay thay IP của Flutter.

**Mỗi khi đổi mạng:** lấy IPv4 ở mục Wi-Fi của `ipconfig`, sửa duy nhất
`localWifiBaseUrl` trong `lib/config/api_config.dart` thành `http://IP_MOI:8000`,
lưu file, bấm Stop rồi ▶ ở cấu hình `main.dart`. Flutter biên dịch lại mã có
địa chỉ mới; backend vẫn nhận kết nối qua `0.0.0.0:8000`, không cần sửa lệnh.
Cấu hình `main.dart` không đặt `--dart-define=API_BASE_URL` để địa chỉ trong file
được sử dụng. Nếu tự thêm tham số này ở **Edit Configurations → Additional run
args**, hãy bỏ nó khi muốn quay lại chỉnh URL bằng `api_config.dart`.

Nếu chạy Flutter bằng terminal, mở backend bằng lệnh sau và giữ terminal mở:

```powershell
.\backend\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

Sau đó chạy Flutter. USB chỉ cần cho việc cài/debug app, **không cần**
`adb reverse` để kết nối backend:

```powershell
flutter pub get
flutter run -d DEVICE_ID
```

Thay `DEVICE_ID` bằng ID trong `adb devices`. Mở
`http://IP_WIFI_MAY_TINH:8000/health` trên trình duyệt điện thoại để thử đường
truyền; phải thấy phản hồi JSON. Nếu IP máy tính thay đổi, sửa duy nhất
`localWifiBaseUrl` trong `lib/config/api_config.dart` hoặc truyền
`--dart-define=API_BASE_URL=http://IP_MOI:8000` khi chạy/build Flutter. Backend
dùng `--host 0.0.0.0` nên không phải đổi lệnh theo IP. Gán IP cố định cho máy tính
trong router (DHCP reservation) sẽ tránh phải cập nhật sau mỗi lần đổi mạng.
Nếu không mở được `/health`, kiểm tra cùng Wi-Fi và tường lửa Windows chỉ cho
phép máy trong mạng tin cậy truy cập TCP 8000; tránh dùng Wi-Fi công cộng.

Sau khi đổi địa chỉ, hãy Stop rồi Run lại để có một phiên chạy mới; không chỉ
dùng hot reload cho việc đổi cấu hình kết nối.

HTTP cleartext chỉ được bật trong Android debug manifest. Bản release không hạ
bảo mật và nên gọi backend qua HTTPS.

## 4. Gợi ý phối đồ và Open-Meteo

Ngay trong **Bối cảnh mong muốn** ở trang phân tích ảnh có nút chuyển
**Thủ công / Thời tiết hiện tại**: chế độ thủ công chọn mùa và nhập nhiệt độ;
chế độ thời tiết hiện số liệu Open-Meteo, nút làm mới và lựa chọn thành phố,
không hiển thị hoặc gửi mùa thủ công. Open-Meteo không cung cấp mùa, nên AI
không suy mùa từ nhiệt độ. Trang **Gợi ý phối đồ** kế thừa chế độ và
dữ liệu thời tiết vừa lấy, không định vị lại nếu dữ liệu còn mới.

Chế độ **Thời tiết hiện tại** xin quyền vị trí trên điện thoại, gửi tọa độ làm
tròn đến backend; backend gọi Open-Meteo (không cần API key). App hiển thị nhiệt
độ, nhiệt độ cảm nhận, mưa của khoảng đo hiện tại (mm) và xác suất mưa cao nhất
trong ngày (%). Nếu GPS tắt, từ chối quyền hoặc định vị quá hạn, có thể chọn
thành phố để vẫn lấy thời tiết. Vị trí chỉ được lấy khi mở chế độ này hoặc bấm
làm mới, không lấy theo từng khung hình camera.

Tab **Gợi ý** và **Hỏi đáp** không dùng ảnh hay loại đồ YOLO nhận diện. Hai tab
chỉ dùng hồ sơ chiều cao/cân nặng/giới tính, phong cách, hoàn cảnh cùng
mùa/nhiệt độ thủ công **hoặc** dữ liệu Open-Meteo hiện tại. Chatbot nhận bối
cảnh mới nhất sau khi đổi lựa chọn.
Khi thời tiết lỗi, nhận diện ảnh vẫn dùng được và có thể chọn chế độ thủ công.
Lần phân tích ảnh tiếp theo gửi dữ liệu thời tiết có cấu trúc cho Gemini đánh
giá trang phục. App ghi nguồn “Dữ liệu thời tiết: Open-Meteo”.

Với Android Emulator, dùng `--dart-define=API_BASE_URL=http://10.0.2.2:8000`.
Điện thoại thật mặc định dùng IP Wi-Fi của máy chạy backend theo mục 3.
Khi triển khai, đặt
`--dart-define=API_BASE_URL=https://TEN_MIEN_BACKEND` lúc build. Mọi màn hình
dùng chung cấu hình URL tại `lib/config/api_config.dart`; HTTP nội bộ chỉ được
phép ở Android debug.

### Gemini gợi ý và chatbot

Thanh tab dưới cùng có **Phân tích**, **Gợi ý**, **Hỏi đáp**, **Cá nhân**.
Tab **Gợi ý** tạo một bộ đồ mới mà không cần và không dùng ảnh: chọn hồ sơ, mùa,
nhiệt độ thủ công hoặc thời tiết Open-Meteo rồi bấm **Gợi ý phối đồ bằng AI**.
Tab **Hỏi đáp** cũng chỉ dùng bối cảnh này. Riêng tab **Phân tích** dùng nhãn YOLO
thực tế: đánh giá các món đã thấy và đề xuất món còn thiếu nếu ảnh chỉ có một
món. Giới tính tự chọn được dùng trong cả ba luồng; hồ sơ Nam có chân váy/váy sẽ
được ghi là cần điều chỉnh và có phương án quần dài/quần short, nhưng vẫn tôn
trọng trường hợp đó là phong cách người dùng chủ động chọn. “Chưa chọn” hoặc
“Không muốn trả lời” không gửi giới tính sang AI. Ảnh gốc không gửi sang Gemini.

Tab **Phân tích** gọi Gemini một lần sau YOLO để đánh giá và bổ sung các món còn
thiếu ngay trên kết quả ảnh. Chuyển sang **Gợi ý** không tái sử dụng ảnh, nhãn
YOLO hay đánh giá này mà tạo gợi ý mới từ hồ sơ và bối cảnh. Nút tạo gợi ý hoặc
câu hỏi trong tab **Hỏi đáp** mới phát sinh request AI; không gọi theo khung hình
camera. Chat lưu tối đa 200 tin nhắn văn bản gần nhất và bản nháp trên thiết bị,
tách riêng theo UID đăng nhập; đổi tab hoặc mở lại app vẫn tiếp tục được cuộc
trò chuyện. Câu hỏi chưa nhận được trả lời có nút **Thử lại**, không tự gửi lại
khi mở app. Mỗi request chỉ gửi sáu lượt gần nhất để tiết kiệm token và không
lưu hội thoại trên Gemini (`store=False`). Nút **Cuộc trò chuyện mới** xóa lịch
sử cục bộ sau khi xác nhận. Lịch sử này chưa đồng bộ sang thiết bị khác.
Không có gợi ý cục bộ giả.

Hồ sơ được chọn đồng bộ giữa Phân tích, Gợi ý, Hỏi đáp, Cá nhân và camera sau
khi lưu Firebase thành công. Xóa hồ sơ không dùng lại số đo cũ. Chế độ thời
tiết, mùa/nhiệt độ thủ công, phong cách và hoàn cảnh của trang Phân tích được
ghi nhớ riêng theo tài khoản; không lưu tọa độ hay dữ liệu thời tiết cũ.
Nếu thiếu hồ sơ hoặc không lấy được thời tiết, vẫn phân tích được ảnh. AI
không chấm điểm tỷ lệ khi thiếu số đo, không chấm mùa/nhiệt độ khi thiếu toàn
bộ dữ liệu thời tiết. Điểm tổng chỉ tính trên các tiêu chí có dữ liệu.

Tạo key tại [Google AI Studio](https://aistudio.google.com/apikey), đặt
`GEMINI_API_KEY=...` trong `backend/.env` (không đặt trong Flutter hay commit),
sau đó cài dependency và khởi động lại backend:

```powershell
.\backend\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
.\backend\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

Model mặc định là `gemini-3.5-flash-lite`; có thể đặt `GEMINI_MODEL` trong
`backend/.env`. Backend chờ Gemini tối đa 45 giây, dùng mức suy luận tối thiểu
và giới hạn đầu ra để tránh cắt phản hồi sớm nhưng không tốn token thừa. Với
Android Emulator, chạy
`flutter run -d EMULATOR_ID --dart-define=API_BASE_URL=http://10.0.2.2:8000`.
Điện thoại thật dùng Wi-Fi LAN như mục 3; khi deploy dùng HTTPS.

## 5. Thử đồ ảo realtime

Mở **Thử đồ ảo** trên màn hình phân tích. Flutter lấy image stream camera, xoay
đúng chiều, resize tối đa 640 px, nén JPEG quality 68 trong isolate rồi gửi
khoảng 8 FPS. Chỉ có một frame đang chờ; frame đến trong lúc backend bận bị bỏ
để ưu tiên hình mới và tránh độ trễ tích lũy.

Địa chỉ WebSocket được sinh tập trung từ `API_BASE_URL`: `http` đổi thành `ws`,
`https` đổi thành `wss`, sau đó nối `/api/v1/pose/ws`. Thông điệp đầu tiên là:

```json
{
  "type": "config",
  "camera": "front",
  "mirrored": true,
  "rotation_degrees": 0,
  "frame_width": 480,
  "frame_height": 640
}
```

Các thông điệp tiếp theo là binary JPEG. Backend trả `pose_result` gồm
`frame_id`, `timestamp_ms`, `processing_ms`, `pose_detected`, `body_visible`,
33 landmark gồm điểm mặt cơ bản, vai, tay, thân, chân và các anchor
`shoulder_center/width/angle`, `hip_center/width/angle`, `torso_center/height`,
`left_leg_length`, `right_leg_length`. Khi thấy một phần cơ thể, response vẫn có
`pose_detected: true` và các landmark; `body_visible: false` báo chưa đủ điểm
để thử đồ toàn thân. Chỉ khi model không thấy người thì `pose_detected: false`.

Pose Landmarker chạy `VIDEO`, `num_poses=1`, được tải đúng một lần và suy luận
ngoài event loop. Model chính thức nằm tại:

```text
backend/models/pose_landmarker_full.task
```

Backend ưu tiên bản Full nếu có; khi chưa tải thì dùng bản Lite sẵn có.

Nếu cần tải lại model mà không tự tải mỗi lần server khởi động:

```powershell
.\backend\.venv\Scripts\python.exe backend\scripts\download_pose_model.py
```

Có thể điều chỉnh ngưỡng bằng biến môi trường
`POSE_MIN_DETECTION_CONFIDENCE`, `POSE_MIN_PRESENCE_CONFIDENCE`,
`POSE_MIN_TRACKING_CONFIDENCE`, `POSE_VISIBILITY_THRESHOLD` (mặc định `0.5`).

### Thêm PNG filter

Đặt ảnh không nền, không có người mẫu và được cắt sát vào thư mục phù hợp dưới
`assets/try_on/`, rồi thêm một `TryOnFilter` trong
`lib/models/try_on_filter.dart`. Metadata nằm ngoài widget:

```dart
TryOnFilter(
  id: 'shirt_new_01',
  name: 'Áo mới',
  category: TryOnFilterCategory.top,
  assetPath: 'assets/try_on/tops/shirt_new_01.png',
  widthMultiplier: 1.4,
  heightMultiplier: 1.35,
  offsetX: 0,
  offsetY: 0.03,
)
```

Tăng/giảm `widthMultiplier` và `heightMultiplier` để khớp kích thước cơ thể;
`offsetX`, `offsetY` dịch tâm theo tỷ lệ kích thước filter;
`defaultRotation` dùng radian. Người dùng vẫn có thể kéo, chụm và xoay từng
filter, hoặc nhấn reset để về transform tự động.

Camera trước được mirror, preview `BoxFit.cover` được bù phần crop và pose được
làm mượt EMA. WebSocket tự nối lại tối đa ba lần. Độ trễ thực tế còn phụ thuộc
Wi-Fi, CPU máy chạy FastAPI, camera và thiết bị; camera vẫn hiển thị nếu backend
mất kết nối nhưng filter tự động sẽ tạm dừng.

### Dùng ảnh quần áo của bạn làm filter

Trong **Thử đồ ảo**, chọn loại đồ (Áo/Áo khoác/Quần/Chân váy/Váy/Giày),
bấm **Thêm ảnh đồ**, chọn ảnh JPEG/PNG/WebP tối đa 10 MB và 20 megapixel.
Màn **Căn ảnh vào khung** có viền theo loại đồ đã chọn. Kéo ảnh, chụm hai ngón
để phóng/thu hoặc xoay cho món đồ vừa viền. Có thanh phóng/thu, **Lật ảnh**,
**Đặt lại** và **Xem trước**. Bấm **Tạo filter** để cắt theo viền và mặc thử.
Kéo/chụm/xoay hai ngón để căn đồ trên người; nút đặt lại đưa về vị trí tự động.
Muốn bỏ ảnh vừa thêm, bấm biểu tượng thùng rác ở thanh chọn đồ.

Tạo filter hoàn toàn bằng Flutter trên điện thoại, không gọi YOLO, API tách nền
hay Gemini. Phần ngoài viền thành trong suốt; ảnh xuất PNG cạnh tối đa 900 px.
Mọi chi tiết bên trong viền được giữ từ ảnh, vì vậy nên căn món đồ cho kín khung.
Ảnh PNG đã trong suốt vẫn giữ các vùng trong suốt bên trong. Endpoint tách nền
cũ còn phục vụ client cũ nhưng không được dùng trong luồng tạo filter mới.

Camera vẫn dùng MediaPipe qua backend để theo dõi cơ thể. Mặt ảnh quần áo được
uốn bằng lưới tam giác, thêm sáng tối nhẹ và phối cảnh dựa trên độ sâu của vai/hông;
áo co theo tỷ lệ vai/hông. Hiệu ứng giữ độ trong suốt của cổ áo và khe ống quần.

Với ảnh căn theo viền (trừ giày), có thêm **Xem thử 3D** trước khi tạo filter.
Kéo để xoay 360°, chụm hai ngón để phóng/thu; chọn mặt trước/bên/sau, độ phồng
hoặc xem lưới. Bấm **Dùng filter này** để đưa ảnh đã căn vào camera.
Trong camera, dùng **2D / 3D bám thân** để chuyển chế độ hoặc **Xem 360°**
để mở lại bản xem trước. Camera và gửi frame tạm dừng khi xem 3D, rồi được mở
lại khi quay về. Ảnh có sẵn và filter giày vẫn dùng chế độ 2D.

Chế độ 3D dùng mô hình XYZ dựng sẵn bằng mã cho áo, áo khoác, quần, chân váy
và váy liền, có thể tích, cổ/gấu mở, ánh sáng theo pháp tuyến và chiếu phối cảnh.
Ảnh căn được ánh xạ lên mặt trước; mặt bên/sau dùng màu trung bình từ ảnh để
minh họa, không phải chi tiết mặt sau thật. Lưới hình học được cache theo loại,
ảnh giải mã và màu vật liệu chỉ được lấy một lần, không gọi API/Gemini để dựng 3D.
Đây là mô hình mẫu thử nghiệm: chưa tái dựng chính xác quần áo từ một ảnh,
chưa mô phỏng vải, đo độ vừa, tay che trước áo hay uốn từng tay/chân.
Camera dùng `world_landmarks` (mét) từ MediaPipe qua WebSocket để dựng ba trục
của thân theo vai/hông, giữ nguyên trái/phải giải phẫu. Không sắp lại vai theo
màn hình và không giới hạn góc xoay ±43° như cách cũ. Xoay thân đủ vòng có thể
đưa mặt bên và mặt sau của mô hình ra trước camera; quay riêng đầu không xoay áo.
Góc nghiêng/cúi được áp trong không gian 3D, nội suy quaternion 90 ms qua mốc
±180°. Kích thước lấy từ chiều dài xương trong không gian và tỷ lệ chiếu ra
màn hình, không lấy riêng khoảng cách hai vai trên ảnh khi đứng nghiêng.
Camera selfie chỉ lật ảnh sau khi chiếu, không đổi mặt trước/sau của mô hình.

Cần khởi động lại backend sau khi cập nhật để có `world_landmarks`. Thiếu dữ
liệu 3D, vai/hông không đủ tin cậy hoặc thân bị cắt khỏi khung hình thì hiện
hướng dẫn và ẩn áo, không dựng góc xoay giả. Đặt điện thoại cách đủ xa để thấy
vai và hông; quần/váy cần thấy cả chân. Đây không phải quét cơ thể 3D và không
bảo đảm tracking liên tục khi người bị che. Tốc độ đo vẫn phụ thuộc camera,
mã hóa JPEG, mạng và MediaPipe trên backend; nội suy không tạo thêm phép đo.
Phần chiếu/vẽ dùng Flutter [Canvas.drawVertices](https://api.flutter.dev/flutter/dart-ui/Canvas/drawVertices.html).
Camera trước/sau không làm đồ lật ngược;
khung xương mặc định ẩn và có thể bật bằng nút hình người.
Mỗi loại chỉ giữ một ảnh tự nhập trong RAM trong phiên thử đồ. Đóng màn thử đồ
sẽ bỏ các filter tự nhập; không có tủ đồ, lưu ảnh trên server hay Firebase Storage.

## 6. Quyền riêng tư và Firebase

- Firebase Authentication và hồ sơ đăng ký `users/{uid}` vẫn hoạt động.
- Trang **Thông tin cá nhân** hiển thị tên đăng nhập và email; mật khẩu cũ không
  thể đọc lại từ Firebase. Đổi mật khẩu yêu cầu nhập mật khẩu hiện tại để xác
  thực lại, sau đó cập nhật mật khẩu mới qua Firebase Authentication.
- Có thể thêm, đổi tên, sửa số đo, xóa và chọn nhiều hồ sơ cơ thể. Các hồ sơ
  được lưu trong trường `bodyProfiles` của tài liệu Firestore `users/{uid}`;
  dữ liệu cũ trên máy được chuyển lên cloud một lần nếu cloud chưa có hồ sơ.
  Hồ sơ được chọn cung cấp chiều cao/cân nặng cho phân tích ảnh; tên
  hồ sơ cũng hiển thị trong màn hình nhận diện video và thử đồ ảo. Hai chế độ
  video hiện chỉ hiển thị lựa chọn này, chưa dùng số đo để thay đổi xử lý pose.
- Tính năng phân tích không dùng `firebase_storage`, URL Storage, collection tủ
  đồ hoặc lịch sử ảnh trong Firestore.
- Backend đọc ảnh trong RAM để chạy YOLO rồi giải phóng sau request; không ghi
  file ảnh, không upload và không gửi ảnh gốc sang Gemini.
- `shared_preferences` giữ hồ sơ cũ để chuyển dữ liệu, lựa chọn phân tích và
  văn bản hỏi đáp riêng theo tài khoản; không lưu mật khẩu hoặc bytes/path ảnh. Cần quy tắc Firestore chỉ
  cho chủ tài khoản (`request.auth.uid == uid`) đọc/ghi `users/{uid}`.
- Vị trí chỉ được lấy khi chọn chế độ thời tiết hoặc làm mới. Tọa độ được làm
  tròn khoảng 0,01 độ, gửi trong body request tới backend rồi chuyển tới
  Open-Meteo;
  không lưu tọa độ vào hồ sơ người dùng.
- Frame thử đồ chỉ tồn tại trong RAM đủ lâu để MediaPipe xử lý: không ghi file,
  không log binary, không gửi Gemini, Firebase Storage hay Firestore.

## 7. Kiểm thử

```powershell
dart format .
flutter analyze
flutter test
.\backend\.venv\Scripts\python.exe -m pytest backend\tests -v
```

Test dùng YOLO/Gemini/MediaPipe giả nên không gọi dịch vụ mất phí. Test Flutter
bao phủ parse pose JSON, mirror/rotation/crop `BoxFit.cover`, EMA, giới hạn
scale, trạng thái kết nối, cùng các test nhận diện/phân tích có sẵn. Chi tiết
backend và xử lý sự cố nằm tại [backend/README.md](backend/README.md).
