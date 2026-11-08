# ⚡ HyperMac — Siêu Tiện Ích Tất-Cả-Trong-Một Cho Mac (Apple Silicon)

[![Version](https://img.shields.io/badge/version-v1.9.3-blue.svg)](https://github.com/mrgoose000000-gif/HyperMac/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-black.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon%20(arm64)-brightgreen.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![Memory Footprint](https://img.shields.io/badge/RAM-~45MB-success.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![Donate](https://img.shields.io/badge/❤️_Donate-Ủng_hộ-ff69b4.svg)](#-ủng-hộ-phát-triển-donate)

> 🚀 **HyperMac** là bộ công cụ tối thượng viết bằng **Swift thuần** dành riêng cho máy Mac chạy chip **Apple Silicon (M1, M2, M3, M4...)**. Ứng dụng gom trọn tính năng của **9 ứng dụng rời rạc** vào một icon duy nhất trên thanh Menu Bar với mức tiêu hao RAM siêu nhẹ **chỉ ~45MB**:
> 
> **Bartender & Hidden Bar** (Gom gọn thanh Menu Bar) + **CleanMyMac & AppCleaner** (Dọn rác hệ thống & Gỡ app tận gốc) + **Rectangle** (Chia cửa sổ) + **AltTab** (Chuyển cửa sổ đa hàng) + **Finder Cut & Paste** (Cắt & Dán tệp Windows-style) + **Maccy** (Lịch sử Clipboard) + **AlDente Pro** (Khóa sạc 80% SMC) + **BetterDisplay** (Chỉnh sáng màn ngoài F1/F2) + **Nhiệt độ & Cảm biến** (Đo nhiệt độ 30+ cảm biến HID/PMU) + **Đo tốc độ chép file** (ổ vật lý & NAS qua LAN).

---

## 📥 TẢI VỀ & CÀI ĐẶT NHANH (Trong 30 Giây)

### ⬇️ Bước 1: Tải bộ cài dựng sẵn
Bấm vào nút bên dưới để tải về phiên bản mới nhất:

[![Download HyperMac](https://img.shields.io/badge/📥_TẢI_VỀ-HyperMac.zip_(v1.9.3)-2563EB?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/mrgoose000000-gif/HyperMac/releases/latest/download/HyperMac.zip)

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

### 🔐 Bước 4: Cấp quyền hoạt động (Trực quan với 1-chạm)
Từ bản **v1.8.0**, HyperMac tích hợp sẵn thẻ **"Cấp quyền phần mềm"** trực quan ngay tại đầu tab Màn hình:
* Nếu máy chưa đủ quyền, thẻ sẽ báo đỏ nhẹ kèm số lượng quyền còn thiếu.
* Bấm vào thẻ để xổ xuống chi tiết: app giải thích rõ **tại sao cần cấp từng quyền** (Trợ năng, Ghi màn hình, SMC, Bluetooth) và cung cấp sẵn nút **`Cấp quyền ngay` / `Mở Cài đặt`** để mở thẳng trang cài đặt của macOS mà bạn không cần phải tự tìm đường dẫn.
* Khi đã cấp đủ, ô sẽ tự động đổi sang màu xanh/xám dịu và báo **`✓ Đầy đủ quyền`**.

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

### 🧹 9. Dọn Dẹp Rác Hệ Thống & Gỡ Cài Đặt Ứng Dụng (Thay thế CleanMyMac & AppCleaner)
Tích hợp trực tiếp tại tab **Dọn dẹp** trên thanh điều khiển của HyperMac, chia thành 3 phân vùng chuyên sâu:
* **✨ Dọn rác hệ thống (System Junk Cleaner):**
  * Tự động quét song song đa luồng toàn bộ Bộ nhớ đệm (`~/Library/Caches`), Nhật ký lỗi (`~/Library/Logs`), Thùng rác (`~/.Trash`), và Dữ liệu rác Xcode (`DerivedData`).
  * Sử dụng giải thuật C-level `du` đo đếm dung lượng siêu tốc, giải phóng hàng chục GB dung lượng SSD chỉ trong vài giây.
  * Tích hợp dọn sạch Thùng rác qua cầu nối Finder AppleScript chuẩn xác, an toàn, không lo bị chặn quyền macOS.
* **📦 Gỡ bỏ ứng dụng tận gốc (Smart App Uninstaller):**
  * Liệt kê toàn bộ ứng dụng cài đặt trong `/Applications` sắp xếp theo dung lượng thực tế.
  * Tự động truy quét và bóc tách mọi tệp tàn dư (*leftovers*) rải rác trong `Application Support` (kể cả thư mục lồng sâu 2 cấp của Google, Microsoft, Adobe...), `Caches`, `Preferences`, `Saved Application State`, `Containers`, `Group Containers`, `WebKit Data`, `HTTPStorages`.
  * Cơ chế Thùng rác an toàn: Chuyển toàn bộ ứng dụng và tệp rác vào Thùng rác (`~/.Trash`) thay vì xóa vĩnh viễn (`rm -rf`), người dùng có thể khôi phục lại bất kỳ lúc nào nếu đổi ý.
  * Tự động Fallback Finder: Nếu ứng dụng thuộc quyền sở hữu quản trị `root:wheel` (như OneDrive, Microsoft Office), app tự động ủy quyền qua Finder để gỡ bỏ thành công mà không báo lỗi.
* **📂 Dò tìm tệp lớn & tệp cũ (Large Files Finder):**
  * Tùy chọn lọc kích thước: `≥ 100MB`, `≥ 200MB`, `≥ 500MB`, `≥ 1GB` trong các thư mục dung lượng lớn (`Downloads`, `Movies`, `Documents`).
  * Xem nhanh vị trí tệp trong Finder hoặc dọn ngay vào Thùng rác với một chạm.

---

## ❓ CÂU HỎI THƯỜNG GẶP (FAQ)

<details>
<summary><b>1. Máy Mac chip Intel ("Chip I") có dùng được HyperMac không?</b></summary>

> **Không hỗ trợ.** HyperMac được tối ưu chuyên sâu và chỉ hỗ trợ các dòng máy Mac chạy chip **Apple Silicon** (M1, M2, M3, M4...). Do ứng dụng khai thác trực tiếp tập lệnh kiến trúc ARM64, quản lý bypass sạc qua Apple Silicon SMC và đọc cảm biến nhiệt độ phần cứng đặc thù của dòng chip M, nên không thể chạy trên các đời máy Mac cũ dùng chip Intel.
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

### [v1.9.3] — 2026-11-08
- **🗄️ Cải tiến Ngăn kéo Menu Bar (Menu Bar Drawer):** Tích hợp trực tiếp qua macOS Accessibility API (`AXUIElement`), cho phép mở menu thật của từng ứng dụng trên Menu Bar ngay cả khi bị màn hình tai thỏ (MacBook Notch) che khuất.
- **🎯 Quản lý & Đồng bộ danh sách icon:** Tự động phát hiện và đồng bộ thứ tự ứng dụng trên thanh trạng thái theo thời gian thực, ghi nhớ cấu hình ứng dụng ổn định qua Bundle Identifier.
- **🔍 Tìm kiếm & Phím tắt nhanh ⌥⌘B:** Mở khay ứng dụng menu bar tức thì từ bất kỳ đâu bằng phím tắt `⌥⌘B` (Option + Command + B), hỗ trợ ô tìm kiếm lọc ứng dụng nhanh chóng.
- **⚙️ Tối ưu hoá hiệu năng & Giao diện Native:** Giao diện bảng ứng dụng mượt mà chuẩn Apple Human Interface Guidelines, tiêu thụ 0% CPU khi chạy nền, bộ nhớ RAM siêu nhẹ ~45MB.

### [v1.9.2] — 2026-11-08
- **🗄️ Gom gọn Menu Bar (Menu Bar Hider):** Gom toàn bộ các biểu tượng ứng dụng trên thanh trạng thái vào một ô nhỏ, mở rộng/thu gọn tức thì chỉ với 1 click hoặc phím tắt `⌘⌥B`, hỗ trợ tự động ẩn sau 5s/10s, 0% CPU & siêu nhẹ chuẩn native Swift!
- **🪟 Chuẩn hóa thứ tự Alt+Tab:** Đồng bộ 100% theo Z-order thời gian thực từ macOS WindowServer. Chuyển đổi qua lại giữa 2 cửa sổ gần nhất chính xác tuyệt đối, không còn bị nhảy lệch thứ tự khi chuyển tab nhanh.
- **🔋 Khắc phục triệt để lỗi hỏi mật khẩu liên tục khi Khóa sạc 80%:** Loại bỏ vòng lặp gọi chéo giữa trình quản lý Pin và Quạt tản nhiệt. Tích hợp Deep Probe nhận diện Helper v2 đã cài đặt để không bao giờ hỏi lại mật khẩu thừa.
- **🛡️ Hệ thống Quét Quyền Thực Tế (Deep Probe):** Bổ sung nút 'Quét lại quyền' và kiểm tra quyền thật (Accessibility, Ghi màn hình, Helper điều khiển phần cứng), hiển thị banner cảnh báo nổi bật màu cam nếu quyền bị thiếu hoặc bị bỏ qua.

### [v1.9.1] — 2026-11-07
- **📋 Clipboard Lưu ảnh gốc Lossless:** Lưu trữ ảnh chất lượng cao riêng biệt trong thư mục `ClipboardImages`, dán ra giữ nguyên 100% độ sắc nét và nền trong suốt PNG/TIFF, tự động xóa tệp ảnh tương ứng khi xóa mục trên Clipboard.
- **📌 Đổi thứ tự ghi chú ghim (⌘↑ / ⌘↓):** Cho phép hoán đổi vị trí ghi chú ghim nhanh chóng bằng phím tắt `⌘↑` / `⌘↓` hoặc nút bấm trực quan `▲` / `▼`, hiển thị rõ số phím tắt `1`–`9` kèm huy hiệu ghim cam để dán tức thì.
- **🔄 Fix lỗi Auto-Updater & Asset Release:** Trình cập nhật tự động chỉ nhận file ZIP, loại trừ nhầm file DMG, sửa lỗi hiển thị thừa ký tự 'vv' (`Có bản v1.9.1`) và gỡ bỏ file DMG khỏi release.

### [v1.9.0] — 2026-11-06
- **🛡️ Fix khóa sạc 80% trên MacBook Pro Apple Silicon:** Tích hợp Apple Native PowerUI MCL và bộ key SMC firmware mới (`bfF0`/`bfD0`/`bfE0`), đảm bảo khóa sạc 80% chuẩn xác không bị nhảy lên 100%.
- **🖥️ Fix AltTab màn hình dọc:** Tự động co giãn 2 cột theo tỉ lệ màn hình, không còn bị cắt mép phải hay tràn badge tiêu đề.
- **🌀 Điều khiển quạt tản nhiệt:** Thẻ chỉnh quạt dành cho MacBook Pro (`System` / `Medium` / `High` / Slider `RPM`) với cơ chế bảo vệ nhiệt độ thông minh.
- **🎨 Giao diện mới:** Áp dụng `Theme.swift` tối giản, thanh lịch, chuẩn macOS hiện đại.
- **🌐 Đa ngôn ngữ:** Chuyển đổi nhanh Tiếng Việt (`vi`) / Tiếng Anh (`en`) toàn diện trên mọi màn hình.
- **📋 Tùy chọn phím tắt Clipboard:** Linh hoạt chuyển đổi giữa `⌘ + ⇧ + C` hoặc `⌘ + ⇧ + V`.
- **☀️ Phím F1/F2 linh hoạt:** Khi tắt tính năng chỉnh sáng theo trỏ chuột, F1/F2 tự động trả về mặc định điều khiển màn hình của hệ điều hành macOS.
- **📸 Tính năng Screenshot (Chụp màn hình LightShot):** Chụp màn hình chuyên nghiệp với phím tắt `⌘ + ⇧ + 1` (hoặc `F4`), hỗ trợ công cụ vẽ chú thích (bút vẽ, mũi tên, hình chữ nhật, bút dạ quang, bảng màu), `⌘C` sao chép nhanh, `⌘S` lưu vào thư mục Downloads.

### [v1.8.2] — 2026-11-02
- **🌐 Hỗ trợ đa ngôn ngữ Tiếng Việt & Tiếng Anh (i18n Localization):**
  - Bổ sung nút chuyển đổi ngôn ngữ nhanh **`vi` / `en`** trực tiếp tại thanh tiêu đề (bên phải badge phiên bản).
  - Tích hợp hộp thoại xác nhận an toàn trước khi chuyển đổi; ghi nhớ ngôn ngữ đã chọn vĩnh viễn qua `UserDefaults`.
  - Toàn bộ giao diện người dùng (4 tab chính, cài đặt phím tắt, menu dọn rác, overlay AltTab, Clipboard và thông báo pin SMC) được dịch song ngữ chuẩn xác, tự nhiên.
- **✨ Đồng bộ cập nhật & hoàn thiện giao diện:**
  - Tối ưu hóa kích thước và độ sắc nét cho nút chuyển ngôn ngữ và các bảng điều khiển overlay.

### [v1.8.1] — 2026-11-02
- **❤️ Tích hợp nút Donate ủng hộ tác giả:**
  - Bổ sung nút **❤️ Donate** ở thanh điều hướng dưới chân popover, mở modal quét mã QR ngân hàng tiện lợi với thông điệp tri ân người dùng.
- **📋 Tối ưu phím tắt mở Clipboard HUD:**
  - Chuẩn hóa dùng duy nhất tổ hợp phím **`⌘ + ⇧ + C`** để mở bảng lịch sử Clipboard, giải phóng hoàn toàn tổ hợp `⌘ + ⇧ + V` cho các tác vụ *Paste and Match Style* mặc định của macOS và ứng dụng khác.
- **🪟 Chuẩn hóa tính năng Căn giữa cửa sổ (Center Window - Rectangle Standard):**
  - Giữ nguyên 100% kích thước (width x height) ban đầu của cửa sổ khi căn giữa, không tự ý thu nhỏ cửa sổ về kích thước mặc định như trước.
  - Khắc phục triệt để hiện tượng cửa sổ bị co cụm lại "nhỏ xíu" ở giữa màn hình khi dùng màn hình ngoài độ phân giải cao hoặc đa màn hình trên Mac mini.
  - Hỗ trợ thêm tổ hợp phím tắt chuẩn `⌃⌥C` (bên cạnh `⌃⌥⌫ / ⌃⌥Delete`) để căn giữa nhanh 1-chạm.
- **⚡ Tối ưu hóa đo lường nguồn điện & khởi động:**
  - Sửa lỗi hiển thị nhầm "Nguồn AC trực tiếp" và công suất củ sạc khi đang dùng pin cắm màn hình ngoài.
  - Loại bỏ hoàn toàn hộp thoại hỏi mật khẩu quản trị ngoài ý muốn khi mở app.

### [v1.8.0] — 2026-11-02
- **🛡️ Trung tâm Cấp quyền phần mềm (Permissions Hub):**
  - Tích hợp thẻ quản lý quyền trực quan ngay đầu tab Màn hình.
  - Tự động báo đỏ nhẹ khi hệ thống chưa đủ quyền; bấm mũi tên xổ xuống hiển thị chi tiết trạng thái, lý do cần cấp cho từng quyền (Trợ năng, Ghi màn hình, SMC Helper, Bluetooth Sleep Guard).
  - Tích hợp các nút 1-chạm mở thẳng đúng trang Cài đặt tương ứng trong macOS System Settings, tự động chuyển màu xanh khi cấp đủ.
- **☕ Chuyển Chống sleep màn hình sang tab Phím tắt:**
  - Di dời thẻ Caffeinate sang tab Phím tắt, nằm cạnh mục Khởi động cùng macOS để gom gọn các tiện ích hệ thống vào cùng một nơi.
- **🧹 Tích hợp mô-đun Dọn dẹp & Gỡ ứng dụng (CleanMyMac & AppCleaner Replacement):**
  - Bổ sung tab thứ 4 **Dọn dẹp** trên thanh Menu Bar của HyperMac, chia làm 3 phân vùng chuyên sâu.
  - **✨ Dọn rác hệ thống (System Junk Cleaner):** Quét song song đa luồng toàn bộ Caches, Logs, Trash và Xcode DerivedData. Dọn dẹp sạch sẽ hàng chục GB dung lượng an toàn với thuật toán C-level `du`. Tích hợp làm sạch Thùng rác qua cầu nối Finder AppleScript không cần quyền Full Disk Access.
  - **📦 Gỡ bỏ ứng dụng tận gốc (Smart App Uninstaller):** Tự động phát hiện và bóc tách toàn bộ tệp tàn dư (*leftovers*) trong `Application Support` (kể cả thư mục lồng sâu 2 cấp của Google, Microsoft, Adobe...), `Caches`, `Preferences`, `Saved Application State`, `Containers`, `Group Containers`, `WebKit Data`, `HTTPStorages`.
  - **🛡️ Cơ chế Thùng rác an toàn & Fallback Finder:** Toàn bộ ứng dụng và tệp gỡ bỏ được đưa vào `~/.Trash` (thay vì xóa vĩnh viễn), có thể khôi phục lại dễ dàng. Tự động chuyển giao quyền qua Finder khi gỡ ứng dụng thuộc quyền sở hữu quản trị `root:wheel` (như OneDrive, MS Office).
  - **📂 Dò tìm tệp lớn & cũ (Large & Old Files Finder):** Lọc nhanh tệp `≥ 100MB`, `≥ 200MB`, `≥ 500MB`, `≥ 1GB` trong Downloads, Movies, Documents. Mở nhanh trong Finder hoặc đưa vào Thùng rác 1-chạm.

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

## 💖 Ủng Hộ Phát Triển (Donate)

HyperMac là dự án phần mềm mã nguồn mở hoàn toàn **miễn phí** và phi lợi nhuận. Nếu HyperMac giúp ích cho công việc và trải nghiệm sử dụng máy Mac hàng ngày của bạn, việc gửi tặng tác giả một ly cà phê là nguồn động viên vô cùng to lớn để mình tiếp tục duy trì và nâng cấp phần mềm! ☕✨

<div align="center">

<img src="Resources/donate_qr.jpg" alt="Mã QR Donate HyperMac" width="260" style="border-radius: 12px; box-shadow: 0 4px 16px rgba(0,0,0,0.12);" />

<br/>

**Nguyễn Khắc Đại**  
*Quét mã bằng mọi ứng dụng ngân hàng / ví điện tử*

> *"Thật sự cảm ơn bạn đã nhấn vào nút này, từ tận đáy lòng, mình luôn trân trọng số tiền mọi người ủng hộ kể cả ít hay nhiều, điều đó cho mình một động lực rất lớn để tiếp tục phát triển phần mềm này.*  
> *Mình xin chân thành cảm ơn tấm lòng của mọi người 😊😊😊.*  
> *Nếu được, rất mong bạn có thể nhắn cho mình thông tin donate qua FB để mình có thể gửi lời cảm ơn trực tiếp đến bạn ❤️"*

[![Nhắn tin Facebook cho tác giả](https://img.shields.io/badge/💬_Nhắn_tin_qua_Facebook_cho_tác_giả-1877F2?style=for-the-badge&logo=facebook&logoColor=white)](https://bit.ly/4ectK8U)

</div>

---

## 👤 Tác Giả & Bản Quyền
- Dự án mã nguồn mở phát triển bởi **Nguyễn Khắc Đại** ([@khacdai24](https://github.com/khacdai24)) & [mrgoose000000-gif](https://github.com/mrgoose000000-gif).
- Phát hành miễn phí dưới giấy phép **MIT License**.
