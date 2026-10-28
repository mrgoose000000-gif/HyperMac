# ⚡ HyperMac — Siêu Tiện Ích Tất-Cả-Trong-Một Cho Mac (Apple Silicon & Intel)

[![Version](https://img.shields.io/badge/version-v1.6.0-blue.svg)](https://github.com/mrgoose000000-gif/HyperMac/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-black.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![Architecture](https://img.shields.io/badge/architecture-Universal%202%20(Apple%20Silicon%20%26%20Intel)-brightgreen.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![Memory Footprint](https://img.shields.io/badge/RAM-~45MB-success.svg)](https://github.com/mrgoose000000-gif/HyperMac)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

> 🚀 **HyperMac** là bộ công cụ tối thượng viết bằng **Swift thuần** dành cho máy Mac (cả chip Apple Silicon M-series lẫn chip Intel). Ứng dụng gom trọn tính năng của **6 ứng dụng rời rạc** vào một icon duy nhất trên thanh Menu Bar với mức tiêu hao RAM siêu nhẹ **chỉ ~45MB**:
> 
> **Rectangle** (Chia cửa sổ) + **AltTab** (Chuyển cửa sổ trực quan) + **Maccy** (Lịch sử Clipboard) + **AlDente Pro** (Khóa sạc 80% SMC) + **BetterDisplay** (Chỉnh sáng màn ngoài F1/F2) + **Nhiệt độ & Cảm biến** (Đo nhiệt độ 30+ cảm biến HID/PMU) + **Đo tốc độ chép file** (ổ vật lý & NAS qua LAN).

---

## 📥 TẢI VỀ & CÀI ĐẶT NHANH (Trong 30 Giây)

### ⬇️ Bước 1: Tải bộ cài dựng sẵn
Bấm vào nút bên dưới để tải về phiên bản mới nhất:

[![Download HyperMac](https://img.shields.io/badge/📥_TẢI_VỀ-HyperMac.zip_(v1.6.0)-2563EB?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/mrgoose000000-gif/HyperMac/releases/latest/download/HyperMac.zip)

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
Để các tính năng chia cửa sổ và phím tắt hoạt động mượt mà, hãy bật 2 quyền sau:
1. **Trợ năng (Accessibility):** Vào *Cài đặt hệ thống ➔ Quyền riêng tư & Bảo mật ➔ Trợ năng* $\rightarrow$ Gạt bật **HyperMac**. (Dùng để nhận phím tắt chia cửa sổ, F1/F2 và AltTab).
2. **Ghi màn hình (Screen Recording - Tùy chọn):** Vào *Quyền riêng tư & Bảo mật ➔ Ghi màn hình & Âm thanh hệ thống* $\rightarrow$ Gạt bật **HyperMac** để hiển thị ảnh chụp nội dung thực tế trong thẻ chuyển tab AltTab.
3. **Quyền điều khiển sạc pin SMC:** Khi bật nút *"Bật bảo vệ & Khóa sạc 80%"*, app sẽ hỏi xác nhận Touch ID/mật khẩu 1 lần duy nhất để cài đặt helper điều khiển nguồn an toàn.

---

## 🎮 BẢNG HƯỚNG DẪN SỬ DỤNG & PHÍM TẮT

HyperMac nằm gọn gàng trên thanh Menu Bar góc trên bên phải (biểu tượng `⌘`). Dưới đây là phím tắt của các tính năng:

### 🪟 1. Chia Cửa Sổ (Thay thế Rectangle)
Điều khiển cửa sổ siêu tốc độ trễ 0ms, tự động căn chuẩn tỷ lệ khi chuyển màn hình:

| Thao tác | Phím tắt mặc định | Mô tả |
| :--- | :--- | :--- |
| **Nửa trái** | `⌃ Control + ⌥ Option + ←` | Cửa sổ chiếm 50% bên trái |
| **Nửa phải** | `⌃ Control + ⌥ Option + →` | Cửa sổ chiếm 50% bên phải |
| **Toàn màn hình** | `⌃ Control + ⌥ Option + ↵` (hoặc `↑`) | Phóng to cửa sổ đầy màn hình |
| **Căn giữa** | `⌃ Control + ⌥ Option + ↓` | Thu cửa sổ về chính giữa màn hình |
| **Chuyển sang màn hình khác** | `⌃ Control + ⌥ Option + ⌘ Command + →` | Chuyển cửa sổ sang màn hình phụ/chính |

---

### 🔀 2. Chuyển Đổi Cửa Sổ Trực Quan (Thay thế AltTab)
Trình chuyển đổi cửa sổ dạng xem trước trực quan (Thumbnail Live Preview) cực xịn:
* **Mở trình chuyển đổi:** Nhấn giữ **`⌘ Command + Tab`** (hoặc `⌥ Option + Tab`).
* **Chuẩn MRU:** Đảo nhanh giữa 2 cửa sổ gần nhất chỉ bằng 1 cú nhấp thả.
* **Điều hướng:**
  * Bấm `Tab` để chọn tiếp, bấm `~` để lùi lại.
  * Bấm phím **`W`**: Đóng nhanh cửa sổ đang chọn.
  * Bấm phím **`Q`**: Thoát hẳn ứng dụng đó (`Quit`).
  * Bấm phím **`Esc`**: Hủy chuyển đổi.

---

### 📋 3. Lịch Sử Clipboard (Thay thế Maccy)
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

### 🔋 4. Khóa Sạc Pin 80% & Sleep Guard (Thay thế AlDente Pro)
Bảo vệ phần cứng tối đa, đặc biệt phù hợp cho các dòng MacBook cắm sạc liên tục:
* **Khóa sạc ở 80% (SMC AC Bypass):** Ghi trực tiếp vào chip điều khiển nguồn Apple Silicon, ngắt dòng điện vào cell pin khi đạt 80%. Máy chuyển sang chạy điện củ sạc 100%, triệt tiêu nguy cơ phồng pin, chai pin.
* **Nút Sạc Đầy (Top-Up 100%):** Bấm nút sạc đầy tạm thời khi chuẩn bị mang máy ra ngoài.
* **Sleep Guard:** Tự động duy trì lệnh ngắt sạc khi gập máy và tự tắt Bluetooth để chống tụt pin qua đêm (0% hao hụt pin).

---

### 🖥️ 5. Màn Hình Ngoài & Chỉnh Độ Sáng (Thay thế BetterDisplay)
* **Chỉnh sáng màn hình ngoài bằng `F1 / F2`:** Bấm phím F1/F2 trên bàn phím Mac để tăng/giảm độ sáng màn hình rời thông qua chuẩn phần cứng DDC/CI.
* **Ngắt mềm màn ngoài (Software Sleep):** Tắt tạm thời tín hiệu màn ngoài khi không dùng mà không cần rút dây cáp Type-C/HDMI.

---

### ☕ 6. Chống Ngủ Màn Hình (Thay thế Amphetamine)
* Nhấp vào biểu tượng ly cafe trên menu HyperMac để giữ màn hình luôn sáng khi đang render video, tải file nặng hoặc thuyết trình (`15 phút`, `30 phút`, `1 giờ`, `Vô hạn`).

---

### 🖱️ 7. Mẹo Chuột: Mở Mission Control Siêu Nhanh
* Nhấp đồng thời **Chuột Trái + Chuột Phải** (hoặc nhấn giữ chuột trái rồi click chuột phải) $\rightarrow$ HyperMac sẽ lập tức mở **Mission Control** mà không cần với tay lên bàn phím!

---

## ❓ CÂU HỎI THƯỜNG GẶP (FAQ)

<details>
<summary><b>1. Máy Mac chip Intel ("Chip I") có dùng được HyperMac không?</b></summary>

> **Không.** HyperMac được thiết kế và biên dịch tối ưu chuyên sâu 100% cho chip **Apple Silicon ARM64 (M1, M2, M3, M4)**. Các dòng máy Mac cũ chạy vi xử lý Intel có cấu trúc vi điều khiển SMC và driver màn hình khác biệt nên không tương thích.
</details>

<details>
<summary><b>2. Dùng bàn phím cơ ngoài (Aula, Keychron, RK...) bấm F3 lại bị chuyển tab?</b></summary>

> Hiện tượng này là do firmware của bàn phím cơ ngoài ở chế độ Windows tự động phát macro `Cmd+Tab` khi bấm F3.
> 
> **Cách xử lý:**
> - Bấm **`Fn + F3`** để gửi tín hiệu F3 nguyên bản.
> - Hoặc dùng phím tắt chuẩn macOS: **`Control + Mũi tên lên (⌃ + ↑)`** để mở Mission Control.
> - Hoặc click đồng thời **Chuột Trái + Chuột Phải** để mở Mission Control bằng chuột.
</details>

<details>
<summary><b>3. Làm thế nào để HyperMac tự động chạy khi mở máy Mac?</b></summary>

> Vào **Cài đặt hệ thống (System Settings) ➔ Cài đặt chung (General) ➔ Mục đăng nhập (Login Items)**. Tại ô "Mở khi đăng nhập", bấm dấu `+` và chọn file **`HyperMac.app`** trong thư mục Applications.
</details>

<details>
<summary><b>4. Cập nhật phiên bản mới như thế nào?</b></summary>

> Bạn không cần tải lại thủ công! Chỉ cần bấm vào icon HyperMac trên Menu Bar ➔ Bấm nút **"Kiểm tra cập nhật"** ở chân trang. Khi có bản mới, app sẽ hiển thị nội dung cập nhật, tự tải về và nâng cấp 1-chạm trong 2 giây.
</details>

---

## 🛠️ Dành Cho Lập Trình Viên (Tự Biên Dịch Từ Mã Nguồn)

Yêu cầu: macOS 14.0 trở lên, Apple Silicon Mac (M1/M2/M3/M4), Xcode Command Line Tools.

```bash
# 1. Clone mã nguồn
git clone https://github.com/mrgoose000000-gif/HyperMac.git
cd HyperMac

# 2. Biên dịch và cài đặt tự động
chmod +x build.sh
./build.sh
```

---

## 📝 Nhật Ký Phiên Bản (Changelog)

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
  - Lưu ý: đây là tốc độ của cả card mạng, nên nếu đang tải web/xem phim cùng lúc thì số liệu sẽ cộng gộp.
- **🔍 Biết tiến trình nào đang chép:** ô hiển thị tên tiến trình (Finder, `cp`, `rsync`…) khi nó thực sự chiếm phần lớn lưu lượng, tránh báo nhầm I/O nền.
- **Sửa lỗi giao diện header:** chữ "HyperMac" không còn bị bẻ dòng chữ "c" cuối khi nhãn pin/nhiệt độ dài; nhãn trạng thái pin được rút gọn (`🔋 78%`, `🔌 Cắm điện`).
- **Kèm theo các thay đổi của v1.5.2:** AltTab mở tức thì, Clipboard 500/∞ + tự dọn, gỡ bỏ hoàn toàn Fan Control.

### [v1.5.2] — 2026-10-28
- **AltTab mở tức thì (hết delay ~0.5s):**
  - Bỏ bước chụp ảnh thu nhỏ cửa sổ đồng bộ trên main thread khi vừa bấm `⌘ + Tab`.
  - HUD hiện ngay lập tức bằng icon ứng dụng; ảnh xem trước được chụp nền và cập nhật dần sau đó.
  - Tái sử dụng `NSHostingController` thay vì tạo mới mỗi lần mở (hết nháy, giữ vị trí cuộn).
  - Sửa trạng thái kẹt `gIsAltTabVisible` khi danh sách cửa sổ rỗng (không còn nuốt phím `W`/`Q`).
- **Clipboard History linh hoạt hơn:**
  - Thêm giới hạn **500 mục** và **∞ Không giới hạn**.
  - Thêm mục **Tự động xoá** theo tuổi: Không / 7 / 30 / 90 ngày (áp dụng cho mục chưa ghim).
  - Thêm nút **Dọn ngay** để người dùng chủ động dọn bớt lịch sử cũ.
  - **Dọn ngay giờ có phản hồi rõ ràng**: báo "Đã xoá N mục" hoặc "Không có mục nào cũ hơn 30 ngày" (trước đây bấm không thấy gì vì lịch sử toàn mục mới).
  - Thêm nút **Xoá tất cả** (giữ mục đã ghim) — bấm 2 lần để xác nhận, dùng khi muốn dọn ngay lập tức.
  - Khi chọn "Không giới hạn", giao diện nhắc bật tự động xoá để tránh phình bộ nhớ.
- **Phím tắt Clipboard hoạt động đúng như hướng dẫn:**
  - `1–9` dán nhanh, `↑/↓` di chuyển, `↵` dán mục đang chọn, `⌥P` ghim, `⌥⌫` xoá, `⎋` đóng.
  - Sửa lỗi `↵` luôn dán mục đầu tiên thay vì mục đang chọn.
- **Giao diện dễ đọc hơn:** Tăng cỡ ký hiệu phím tắt trong bảng Clipboard HUD và thẻ cài đặt.
- **Gỡ bỏ hoàn toàn Fan Control:**
  - Xoá bảng điều khiển quạt, 4 chế độ quạt, slider RPM và Smart Curve.
  - Bỏ mọi lệnh ghi SMC / `displaycontrol-power` cho quạt; chỉ giữ đo nhiệt độ HID/PMU.
  - Menu Bar chỉ còn hiển thị nhiệt độ (`44°C`).

### [v1.5.1] — 2026-10-28
- **Tích Hợp Hoàn Hảo Động Cơ Macs Fan Control & Sửa Nhận Diện Quạt M1 Max:**
  - **Khắc phục nhận diện quạt trên M1 Max / Pro / Studio / Mini**: Tự động nhận diện chính xác phần cứng có quạt tản nhiệt chủ động.
  - **4 Chế độ quạt chuyên nghiệp**: Tự động (Apple Default), Cố định RPM (Manual với các mốc gợi ý), Theo cảm biến (Smart Curve tuyến tính an toàn), và Tối đa 100% (Turbo Boost).
  - **Giám sát trực tiếp trên Menu Bar**: Tùy chọn hiển thị nhiệt độ tức thời (`44°C`) và tốc độ quạt (`44°C • 1.5k`) ngay cạnh biểu tượng ứng dụng trên thanh trạng thái macOS.
  - **Cơ chế an toàn phần cứng SMC**: Tự động trả quạt về chế độ Auto an toàn của Apple khi máy Sleep, Wake hoặc thoát ứng dụng.
  - **Loại bỏ cơ chế hạ nhiệt cưỡng bức**: Loại bỏ hoàn toàn đóng băng tiến trình ngầm (`SIGSTOP`) để ngăn ngừa đơ ứng dụng.
- **Sửa Triệt Để Lỗi Màn Hình Ảo (Virtual Display):**
  - Xây dựng cầu nối ARC Objective-C `VirtualDisplayBridge` giải phóng bộ nhớ `CGVirtualDisplay` khi tắt màn ảo, ngăn chặn xuất hiện màn hình ảo phantom `U280-Pro`.
- **Gộp Pull Request #1:**
  - Giải quyết triệt để xung đột phím tắt Clipboard Manager (`Cmd+Shift+C`/`V`) với các bộ gõ tiếng Việt (GoTiengViet, EVKey).

### [v1.5.0] — 2026-10-27
- **Tích Hợp Kiểm Soát Nhiệt & Quạt Tản Nhiệt (Macs Fan Control + Apple Silicon Thermal Suite):**
  - **Đọc trực tiếp 30+ cảm biến nhiệt PMU HID**: Đo nhiệt độ từng nhân CPU (P-Core, E-Core), GPU clusters, SSD NAND NVMe, cell pin và bo mạch trong thời gian thực.
  - **Kiểm soát nhiệt thụ động cho MacBook Air (Fanless)**: Cung cấp tính năng ❄️ *Hạ nhiệt tức thì (Đóng băng tiến trình ngầm)* qua `kill -STOP` giúp chip M-series hạ ngay 15–20°C trong 10 giây mà không làm mất tab trình duyệt.
  - **4 Chế độ quạt cho MacBook Pro / Mac Studio / Mac mini**: Tự động (Apple default), Tùy chỉnh (Manual RPM Slider), Tối đa 100% (Boost Cooling), và Tự động theo nhiệt (Smart Curve).
  - **Pill nhiệt độ trực tiếp trên Menu Bar Header**: Theo dõi độ nóng của máy trong nháy mắt.
- **Hỗ Trợ Toàn Diện Universal 2 (Apple Silicon & Intel):**
  - Đóng gói mã nhị phân kép (`arm64` + `x86_64`) trong 1 file cài duy nhất. Tự động tương thích 100% native cả máy Mac M-series lẫn máy Mac dùng chip Intel Core i3/i5/i7/i9.

### [v1.4.7] — 2026-10-26
- **Sửa Lỗi Tự Tắt/Crash Khi Gập Màn Hình MacBook (Sleep Guard TCC Crash Fix):**
  - Khắc phục lỗi bảo mật TCC `SIGABRT` khi máy chuyển sang chế độ ngủ. Bổ sung đầy đủ quyền `NSBluetoothAlwaysUsageDescription` và bộ lọc bảo vệ an toàn trong code.
- **Tối Ưu Hóa Bộ Nhớ RAM (-76% Footprint):**
  - Giảm Physical RAM footprint từ ~150MB xuống chỉ còn **~35MB – 44MB**.
  - Tự động downsample ảnh chụp màn hình AltTab và nén ảnh clipboard sang định dạng JPEG chất lượng cao.
  - Tự động thu hồi và giải phóng bộ nhớ ngay sau khi đóng overlay AltTab.
- **Chuyển Cửa Sổ Đa Màn Hình Chuẩn Rectangle:**
  - Hoàn thiện thuật toán tính tỷ lệ khung hình relativePositionedRect, giữ nguyên 100% kích thước cửa sổ khi chuyển giữa màn Retina và màn hình ngoài.

---

## 👤 Tác Giả & Bản Quyền
- Dự án mã nguồn mở phát triển bởi **Nguyễn Khắc Đại** ([@khacdai24](https://github.com/khacdai24)) & [mrgoose000000-gif](https://github.com/mrgoose000000-gif).
- Phát hành miễn phí dưới giấy phép **MIT License**.
