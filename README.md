# ⚡ HyperMac — Siêu Tiện Ích Tất-Cả-Trong-Một Cho Mac (Apple Silicon & Intel)

[![Version](https://img.shields.io/badge/version-v1.7.0-blue.svg)](https://github.com/mrgoose000000-gif/HyperMac/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-black.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![Architecture](https://img.shields.io/badge/architecture-Universal%202%20(Apple%20Silicon%20%26%20Intel)-brightgreen.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![Memory Footprint](https://img.shields.io/badge/RAM-~45MB-success.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

> 🚀 **HyperMac** là bộ công cụ tối thượng viết bằng **Swift thuần** dành cho máy Mac (cả chip Apple Silicon M-series lẫn chip Intel). Ứng dụng gom trọn tính năng của **7 ứng dụng rời rạc** vào một icon duy nhất trên thanh Menu Bar với mức tiêu hao RAM siêu nhẹ **chỉ ~45MB**:
> 
> **Rectangle** (Chia cửa sổ) + **AltTab** (Chuyển cửa sổ đa hàng) + **Finder Cut & Paste** (Cắt & Dán tệp Windows-style) + **Maccy** (Lịch sử Clipboard) + **AlDente Pro** (Khóa sạc 80% SMC) + **BetterDisplay** (Chỉnh sáng màn ngoài F1/F2) + **Nhiệt độ & Cảm biến** (Đo nhiệt độ 30+ cảm biến HID/PMU) + **Đo tốc độ chép file** (ổ vật lý & NAS qua LAN).

---

## 📥 TẢI VỀ & CÀI ĐẶT NHANH (Trong 30 Giây)

### ⬇️ Bước 1: Tải bộ cài dựng sẵn
Bấm vào nút bên dưới để tải về phiên bản mới nhất:

[![Download HyperMac](https://img.shields.io/badge/📥_TẢI_VỀ-HyperMac.zip_(v1.7.0)-2563EB?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/mrgoose000000-gif/HyperMac/releases/latest/download/HyperMac.zip)

*(Hoặc vào trang [GitHub Releases](https://github.com/mrgoose000000-gif/HyperMac/releases) để xem danh sách tất cả các bản phát hành).*

---

### 📦 Bước 2: Cài đặt vào máy
1. Nhấp đúp vào tệp **`HyperMac.zip`** vừa tải về để giải nén ra ứng dụng **`HyperMac.app`**.
2. **Kéo tệp `HyperMac.app` vào thư mục `Applications` (Ứng dụng)** của máy Mac.

---

### 🛡️ Bước 3: Mở app & Xử lý cảnh báo bảo mật macOS (Làm 1 lần duy nhất)

Do HyperMac là phần mềm mã nguồn mở miễn phí (chưa mua chứng chỉ Apple Developer trả phí 99$/năm), khi bạn mở app lần đầu, macOS Gatekeeper sẽ hiện thông báo:
> *"HyperMac Not Opened: Apple could not verify that HyperMac is free of malware..."*

Để mở app, bạn chỉ cần chọn **1 trong 2 cách** rất đơn giản:

#### 👉 Cách A: Dùng chuột (Không cần gõ lệnh)
1. Bấm nút **Done** trên bảng thông báo cảnh báo.
2. Mở **Cài đặt hệ thống (System Settings)** ➔ chọn mục **Quyền riêng tư & Bảo mật (Privacy & Security)**.
3. Cuộn xuống mục **Bảo mật (Security)**, bạn sẽ thấy thông báo *"HyperMac was blocked..."*.
4. Bấm nút **"Open Anyway" (Vẫn mở)** ➔ Quét Touch ID hoặc nhập mật khẩu máy để xác nhận.

#### 👉 Cách B: Dùng Terminal (Nhanh nhất trong 1 giây)
Mở ứng dụng **Terminal** trên Mac, dán dòng lệnh sau rồi ấn **Enter**:
```bash
xattr -cr /Applications/HyperMac.app
```
Sau đó mở HyperMac bình thường từ Spotlight (`Cmd + Space` gõ `HyperMac`) hoặc trong Launchpad!

---

### 🔐 Bước 4: Cấp quyền hoạt động
Để các tính năng chia cửa sổ và phím tắt hoạt động mượt mà, hãy bật các quyền sau:
1. **Trợ năng (Accessibility):** Vào *Cài đặt hệ thống ➔ Quyền riêng tư & Bảo mật ➔ Trợ năng* $\rightarrow$ Gạt bật **HyperMac**. (Dùng để nhận phím tắt chia cửa sổ, F1/F2, AltTab và Cắt tệp Finder).
2. **Ghi màn hình (Screen Recording - Tùy chọn):** Vào *Quyền riêng tư & Bảo mật ➔ Ghi màn hình & Âm thanh hệ thống* $\rightarrow$ Gạt bật **HyperMac** để hiển thị ảnh chụp nội dung thực tế trong thẻ chuyển tab AltTab.
3. **Quyền điều khiển sạc pin SMC:** Khi bật nút *"Bật bảo vệ & Khóa sạc 80%"*, app sẽ hỏi xác nhận Touch ID/mật khẩu 1 lần duy nhất để cài đặt helper điều khiển nguồn an toàn.

> 💡 **Sau khi cập nhật lên bản mới:** HyperMac tự kiểm tra và khôi phục quyền Trợ năng. Bản phát hành v1.6.0 trở đi được ký bằng chứng chỉ cố định, nên các lần cập nhật sau không còn bị mất quyền nữa.

---

## 🎮 BẢNG HƯỚNG DẪN SỬ DỤNG & PHÍM TẮT

HyperMac nằm gọn gàng trên thanh Menu Bar góc trên bên phải (biểu tượng `⌘`). Dưới đây là phím tắt của các tính năng:

### ✂️ 1. Cắt & Dán Tệp Trong Finder (Giống Ctrl+X ➔ Ctrl+V trên Windows)
Mang cơ chế Cut & Paste quen thuộc từ Windows lên Finder của macOS:
* **Cắt tệp / thư mục:** Chọn tệp trong Finder và bấm **`⌘ Command + X`**.
  * HyperMac sẽ nhận diện và đưa tệp vào trạng thái Cắt, hiển thị thông báo nổi (HUD Toast): `✂️ Đã cắt: [Tên tệp] • Bấm ⌘V để di chuyển • Esc để hủy` kèm âm thanh phản hồi nhẹ.
* **Dán / Di chuyển tệp:** Di chuyển tới thư mục đích và bấm **`⌘ Command + V`**.
  * Tệp sẽ được di chuyển tức thì (*Move Item Here*) vào thư mục mới thay vì phải bấm tổ hợp `⌥ Option + ⌘ Command + V` khó nhớ của macOS.
* **Hủy lệnh cắt:** Bấm phím **`Esc`** hoặc bấm **`⌘ Command + C`** (chuyển sang sao chép bình thường).
* **Thông minh khi đổi tên:** Tự động phát hiện khi bạn đang đổi tên tệp (*rename*) hoặc gõ tìm kiếm để giữ nguyên chức năng cắt văn bản bình thường.

---

### 🪟 2. Chia Cửa Sổ (Thay thế Rectangle)
Điều khiển cửa sổ siêu tốc độ trễ 0ms, tự động căn chuẩn tỷ lệ khi chuyển màn hình:

| Thao tác | Phím tắt mặc định | Mô tả |
| :--- | :--- | :--- |
| **Nửa trên** | `⌃ Control + ⌥ Option + ↑` | Cửa sổ chiếm 50% bên trên |
| **Nửa dưới** | `⌃ Control + ⌥ Option + ↓` | Cửa sổ chiếm 50% bên dưới |
| **Nửa trái** | `⌃ Control + ⌥ Option + ←` | Cửa sổ chiếm 50% bên trái |
| **Nửa phải** | `⌃ Control + ⌥ Option + →` | Cửa sổ chiếm 50% bên phải |
| **Toàn màn hình** | `⌃ Control + ⌥ Option + ↵ Return` | Phóng to cửa sổ đầy màn hình |
| **Căn giữa** | `⌃ Control + ⌥ Option + ⌫ Delete` | Thu cửa sổ về chính giữa màn hình |
| **Chia 4 góc màn hình** | `⌃⌥ + ←↑ / →↑ / ←↓ / →↓`<br>hoặc `⌃⌥ + U / I / J / K`<br>hoặc Numpad `7 / 9 / 1 / 3` | Bố trí cửa sổ vào 1/4 góc màn hình |
| **Sang màn hình khác** | `⌥ Option + ⌘ Command + → / ←` | Di chuyển cửa sổ qua màn hình phụ/chính (scale chuẩn tỷ lệ) |

---

### 🔀 3. Chuyển Đổi Cửa Sổ Trực Quan (Thay thế AltTab)
Trình chuyển đổi cửa sổ dạng xem trước trực quan (Thumbnail Live Preview) cực xịn:
* **Mở trình chuyển đổi:** Nhấn giữ **`⌘ Command + Tab`** (hoặc `⌥ Option + Tab`).
* **Lưới đa hàng thích ứng (Adaptive Grid):** Tự động dàn thành nhiều hàng cân đối, hình ảnh xem trước kích thước lớn (260x188pt), sắc nét và rõ ràng.
* **Điều hướng 4 chiều:** Bấm các phím mũi tên **`↑ ↓ ← →`** để duyệt giữa các hàng và cột; bấm `Tab` để sang ô tiếp theo, `~` để lùi lại.
* **Lọc theo màn hình hiện tại (Multi-Monitor):** Tùy chọn chỉ hiển thị các cửa sổ đang nằm trên màn hình mà con trỏ chuột đang đứng (`[ 🖥️ Màn hình này ]`).
* **Chuẩn MRU:** Đảo nhanh giữa 2 cửa sổ gần nhất chỉ bằng 1 cú nhấp thả.
* **Thao tác nhanh:**
  * Bấm phím **`W`**: Đóng nhanh cửa sổ đang chọn.
  * Bấm phím **`Q`**: Thoát hẳn ứng dụng đó (`Quit`).
  * Bấm phím **`Esc`**: Hủy chuyển đổi.

---

### 📋 4. Lịch Sử Clipboard (Thay thế Maccy)
Lưu trữ lịch sử văn bản, hình ảnh, liên kết, mã màu đã sao chép:
* **Mở Clipboard:** Bấm **`⌘ Command + ⇧ Shift + C`** (hoặc `⌘ + ⇧ + V`).
* **Dán siêu tốc:** Bấm phím số **`1` đến `9`** để dán tức thì dòng tương ứng vào văn bản mà không cần click chuột.
* **Thao tác nhanh:**
  * Bấm **`↵ Enter`**: Dán mục đang chọn.
  * Bấm **`⌥ Option + P`**: Ghim / Bỏ ghim mục quan trọng lên đầu.
  * Bấm **`⌥ Option + ⌫ Delete`**: Xóa mục khỏi lịch sử.
  * Gõ chữ để tìm kiếm nhanh nội dung trong lịch sử.
* **Bảo mật:** Tự động phát hiện và bỏ qua mật khẩu từ Keychain, 1Password, Bitwarden...

---

### 🔋 5. Khóa Sạc Pin 80% & Sleep Guard (Thay thế AlDente Pro)
Bảo vệ phần cứng tối đa, đặc biệt phù hợp cho các dòng MacBook cắm sạc liên tục:
* **Khóa sạc ở 80% (SMC AC Bypass):** Ghi trực tiếp vào chip điều khiển nguồn Apple Silicon, ngắt dòng điện vào cell pin khi đạt 80%. Máy chuyển sang chạy điện củ sạc 100%, triệt tiêu nguy cơ phồng pin, chai pin.
* **Nút Sạc Đầy (Top-Up 100%):** Bấm nút sạc đầy tạm thời khi chuẩn bị mang máy ra ngoài.
* **Sleep Guard:** Tự động duy trì lệnh ngắt sạc khi gập máy và tự tắt Bluetooth để chống tụt pin qua đêm (0% hao hụt pin).

---

### 🖥️ 6. Màn Hình Ngoài & Chỉnh Độ Sáng (Thay thế BetterDisplay)
* **Chỉnh sáng màn hình ngoài bằng `F1 / F2`:** Bấm phím F1/F2 trên bàn phím Mac để tăng/giảm độ sáng màn hình rời thông qua chuẩn phần cứng DDC/CI.
* **Ngắt mềm màn ngoài (Software Sleep):** Tắt tạm thời tín hiệu màn ngoài khi không dùng mà không cần rút dây cáp Type-C/HDMI.

---

### ☕ 7. Chống Ngủ Màn Hình (Thay thế Amphetamine)
* Nhấp vào biểu tượng ly cafe trên menu HyperMac để giữ màn hình luôn sáng khi đang render video, tải file nặng hoặc thuyết trình (`15 phút`, `30 phút`, `1 giờ`, `Vô hạn`).

---

### 🖱️ 8. Mẹo Chuột: Mở Mission Control Siêu Nhanh
* Nhấp đồng thời **Chuột Trái + Chuột Phải** (hoặc nhấn giữ chuột trái rồi click chuột phải) $\rightarrow$ HyperMac sẽ lập tức mở **Mission Control** mà không cần với tay lên bàn phím!

---

## ❓ CÂU HỎI THƯỜNG GẶP (FAQ)

<details>
<summary><b>1. Máy Mac chip Intel ("Chip I") có dùng được HyperMac không?</b></summary>

> **Có hỗ trợ.** HyperMac được đóng gói Universal 2 (chạy native cả Apple Silicon M1/M2/M3/M4 lẫn Intel x86_64). Riêng tính năng bypass pin SMC yêu cầu kiến trúc vi điều khiển tương thích.
</details>

<details>
<summary><b>2. Dùng bàn phím cơ ngoài (Aula, Keychron, RK...) bấm F3 lại bị chuyển tab?</b></summary>

> Hiện tượng này là do firmware của bàn phím cơ ngoài ở chế độ Windows tự động phát macro `Cmd+Tab` khi bấm F3.
> 
> **Cách xử lý:**
> - Bấm **`Fn + F3`** để gửi tín hiệu F3 nguyên bản.
> - Hoặc dùng phím tắt chuẩn macOS: **`Control + Mũi tên lên (⌃ + ↑)`** để mở Mission Control.
> - Hoặc click đồng thời **Chuột Trái + Chuột Phải** để mở Mission Control bằng chuột.
> </details>

<details>
<summary><b>3. Làm thế nào để HyperMac tự động chạy khi mở máy Mac?</b></summary>

> Bạn chỉ cần mở bảng điều khiển HyperMac từ thanh Menu Bar ➔ chuyển sang tab **Phím tắt & Cửa sổ** ➔ Gạt bật mục **"Khởi động cùng macOS"**.
> 
> HyperMac sử dụng dịch vụ nền `SMAppService` chính thức của Apple (hỗ trợ macOS 13, 14, 15+) kèm cơ chế dự phòng `System Events`, tự động kích hoạt ngay khi bạn đăng nhập vào máy mà không cần cấu hình thủ công.
</details>

<details>
<summary><b>4. Cập nhật phiên bản mới như thế nào?</b></summary>

> Bạn không cần tải lại thủ công! Chỉ cần bấm vào icon HyperMac trên Menu Bar ➔ Bấm nút **"Kiểm tra cập nhật"** ở chân trang. Khi có bản mới, app sẽ hiển thị nội dung cập nhật, tự tải về và nâng cấp 1-chạm trong 2 giây.
</details>

<details>
<summary><b>5. Cập nhật xong thì mất quyền Trợ năng / phím tắt không chạy?</b></summary>

> Đây là di chứng của kiểu ký **ad-hoc**: mỗi bản build có "danh tính" (cdhash) khác nhau nên macOS coi là app mới và vô hiệu hoá quyền cũ.
>
> Từ **v1.6.0**, HyperMac được ký bằng **chứng chỉ cố định** và tự động phát hiện, khôi phục quyền Trợ năng sau mỗi lần cập nhật.
</details>

---

## 🛠️ Dành Cho Lập Trình Viên (Tự Biên Dịch Từ Mã Nguồn)

Yêu cầu: macOS 14.0 trở lên, Xcode Command Line Tools.

```bash
# 1. Clone mã nguồn
git clone https://github.com/mrgoose000000-gif/HyperMac.git
cd HyperMac

# 2. Biên dịch và đóng gói tự động
chmod +x build.sh
./build.sh
```

---

## 📝 Nhật Ký Phiên Bản (Changelog)

### [v1.7.0] — 2026-11-01
- **✂️ Cắt & Dán tệp trong Finder (⌘X ➔ ⌘V - Windows Style):**
  - Mang trải nghiệm Cut & Paste tệp / thư mục quen thuộc từ Windows lên Finder của macOS.
  * Bấm `⌘X` để cắt tệp, `⌘V` để di chuyển (thay thế tổ hợp `⌥⌘V` khó nhớ).
  * Hủy cắt tức thì khi bấm `esc` hoặc bấm `⌘C` (sao chép).
  * Tự động nhận diện khi người dùng đang đổi tên tệp (*rename*) hoặc tìm kiếm để giữ nguyên phím tắt cắt văn bản bình thường.
  * Hiển thị thông báo nổi (floating HUD Toast) phản hồi trực quan khi cắt, di chuyển hoặc hủy.
- **🪟 Nâng cấp AltTab đa hàng & Xem trước kích thước lớn:**
  * Phóng to kích thước thumbnail xem trước (260pt x 188pt), ảnh Retina sắc nét giúp nhìn rõ nội dung cửa sổ mà không cần nheo mắt.
  * Chuyển đổi từ bố cục 1 hàng duy nhất thành lưới nhiều hàng tự động cân đối (adaptive multi-row grid).
  * Hỗ trợ các phím mũi tên `↑↓←→` để duyệt linh hoạt qua các hàng và cột trong lưới.
  * Sửa dứt điểm hiện tượng nhiều viền xanh bị kẹt khi chuyển đổi tab nhanh liên tục (loại bỏ LazyVGrid caching, chuyển sang layout đồng bộ 0ms).
- **🖥️ Lọc cửa sổ theo màn hình hiện tại (AltTab Screen-Isolated Mode):**
  * Thêm tùy chọn "Chỉ hiện cửa sổ trên màn hình hiện tại".
  * Khi dùng 2 hoặc nhiều màn hình, AltTab sẽ chỉ hiển thị các cửa sổ đang nằm trên màn hình mà chuột đang đứng, kèm huy hiệu nhận biết `[ 🖥️ Màn hình này ]`.
- **📐 Tùy biến tổ hợp phím Window Snap (Rectangle):**
  * `⌃ + ⌥ + ↑`: Nửa trên (.topHalf)
  * `⌃ + ⌥ + ↓`: Nửa dưới (.bottomHalf)
  * `⌃ + ⌥ + return`: Toàn màn hình (.maximize)
  * `⌃ + ⌥ + delete`: Căn giữa màn hình (.center)
  * Chia 4 góc màn hình: Hỗ trợ chording phím mũi tên liên tiếp (`←↑`, `→↑`, `←↓`, `→↓`) và các phím trực tiếp `U, I, J, K` / Numpad `7, 9, 1, 3`.
  * Hỗ trợ scale cửa sổ theo tỷ lệ chuẩn khi di chuyển qua lại giữa các màn hình có kích thước/độ phân giải khác nhau (`⌥⌘←` / `⌥⌘→`).
- **🚀 Khởi động cùng macOS (Launch at Login):**
  * Tích hợp cơ chế nền kép `SMAppService` (macOS 13+) và AppleScript `System Events` fallback giúp app tự động chạy mượt mà ngay khi đăng nhập máy Mac.
  * Thêm thẻ bật/tắt tiện lợi trong tab *Phím tắt & Cửa sổ*.
- **📂 Giao diện thu gọn (Collapsible Cards):**
  * Bổ sung nút mũi tên chevron (`chevron.down` / `chevron.up`) trên tất cả các thẻ cài đặt lớn giúp bảng điều khiển luôn gọn gàng, thanh thoát.

### [v1.6.0] — 2026-10-28
- **💾 Ô "Chép file" — xem tốc độ truyền file theo thời gian thực:**
  - Nằm trong tab **Pin & Phần cứng**, ngay dưới thanh chọn Pin / Nhiệt độ.
  - **Mặc định tắt** — bật bằng switch trên ô khi cần đo; HyperMac chỉ đo lúc bảng đang mở nên không tốn RAM/CPU khi không dùng.
  - Hiển thị tổng tốc độ đọc `↓` và ghi `↑` (MB/s) của mọi ổ vật lý đang hoạt động.
  - Tự nhận diện tên ổ: SSD nội bộ, USB, thẻ nhớ, SSD ngoài (hiện tên volume đang mount).
  - Dòng chi tiết cho biết **nguồn → đích** của phiên chép, ví dụ `U280-Pro → SSD nội bộ`.
  - Rê chuột vào ô để xem chi tiết từng ổ — hữu ích khi chép thẻ nhớ → ổ rời.
  - Lấy số liệu trực tiếp từ bộ đếm IOKit của ổ vật lý nên không cộng trùng với các volume APFS.
- **🌐 Đo tốc độ NAS qua dây LAN:**
  - Tự dò các ổ mạng đang mount (SMB/AFP/NFS), dùng bảng định tuyến để biết dây LAN nào đang gánh đường tới NAS.
  - Hiển thị tốc độ lên/xuống của interface đó kèm nhãn `LAN en0` / `LAN en1`…
- **🔍 Biết tiến trình nào đang chép:** ô hiển thị tên tiến trình (Finder, `cp`, `rsync`…) khi nó thực sự chiếm phần lớn lưu lượng, tránh báo nhầm I/O nền.
- **Sửa lỗi giao diện header:** chữ "HyperMac" không còn bị bẻ dòng chữ "c" cuối khi nhãn pin/nhiệt độ dài; nhãn trạng thái pin được rút gọn (`🔋 78%`, `🔌 Cắm điện`).
- **🔐 Hết cảnh mất quyền Trợ năng sau mỗi lần cập nhật:**
  - Bản phát hành trên GitHub giờ được ký bằng **chứng chỉ cố định** (identifier + certificate root) thay vì ad-hoc → macOS giữ nguyên quyền qua các phiên bản.
  - App tự phát hiện quyền bị vô hiệu sau update, reset entry TCC bị kẹt và hiện lại hộp thoại xin quyền — không phải xoá app rồi thêm lại.

### [v1.5.2] — 2026-10-28
- **AltTab mở tức thì (hết delay ~0.5s):**
  - Bỏ bước chụp ảnh thu nhỏ cửa sổ đồng bộ trên main thread khi vừa bấm `⌘ + Tab`.
  - HUD hiện ngay lập tức bằng icon ứng dụng; ảnh xem trước được chụp nền và cập nhật dần sau đó.
- **Clipboard History linh hoạt hơn:**
  - Thêm giới hạn **500 mục** và **∞ Không giới hạn**.
  - Thêm mục **Tự động xoá** theo tuổi: Không / 7 / 30 / 90 ngày.
  - Thêm nút **Dọn ngay** và **Xoá tất cả** (giữ mục đã ghim).
- **Phím tắt Clipboard hoạt động chuẩn xác:** `1–9` dán nhanh, `↑/↓` di chuyển, `↵` dán mục đang chọn, `⌥P` ghim, `⌥⌫` xoá.

---

## 👤 Tác Giả & Bản Quyền
- Dự án mã nguồn mở phát triển bởi **Nguyễn Khắc Đại** ([@khacdai24](https://github.com/khacdai24)) & [mrgoose000000-gif](https://github.com/mrgoose000000-gif).
- Phát hành miễn phí dưới giấy phép **MIT License**.
