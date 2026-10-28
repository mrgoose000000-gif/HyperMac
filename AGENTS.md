# AGENTS.md — HyperMac (DisplayControl)

> Tài liệu dành cho AI coding agent (Antigravity IDE, OpenCode, Cursor, Claude Code…) đọc trước khi chỉnh sửa dự án. Cập nhật lần cuối: **2026-10-28 (v1.5.2)**.

## 1. Tổng quan

- **HyperMac** là app menu bar thuần Swift cho macOS 14+ (Apple Silicon), dùng SwiftPM + AppKit + SwiftUI.
- Thư mục làm việc: `/Users/khacdai24/.gemini/antigravity-ide/scratch/DisplayControl`.
- Bundle ID: `com.opensource.hypermac`, tên app: `HyperMac`, chạy ẩn Dock (`LSUIElement`).
- Tính năng: chia cửa sổ (Rectangle), AltTab, lịch sử Clipboard, khóa sạc 80%, chỉnh sáng màn ngoài, chống sleep, đo nhiệt độ.
- **Fan Control đã bị gỡ bỏ hoàn toàn từ v1.5.2.** Không thêm lại logic ghi SMC/điều khiển quạt trừ khi người dùng yêu cầu rõ ràng.

## 2. Build & kiểm tra

```bash
# Chỉ biên dịch (không cài, không kill app đang chạy)
swift build -c release

# Build + đóng gói .app + .zip, KHÔNG cài vào /Applications
./build.sh --no-run

# Build + cài /Applications + chạy (sẽ pkill HyperMac trước)
./build.sh
```

- `xcodebuild` không bắt buộc; máy hiện tại chỉ có Command Line Tools và build bằng SwiftPM.
- Log runtime: `/tmp/displaycontrol.log` (hàm `appLog()` trong `Sources/Logger.swift`).
- App đang chạy: `pgrep -xl HyperMac`.
- **Chữ ký code:** dùng identity self-signed cố định `HyperMac Self-Signed`
  (tạo bởi `./scripts/setup-signing-identity.sh`). Tuyệt đối không quay lại
  `codesign -s -` (ad-hoc) vì mỗi lần build sẽ sinh cdhash mới và macOS thu hồi
  quyền Accessibility → `⌘Tab` / `⌘⇧C` chết. Xem mục 7.

## 3. Bản đồ mã nguồn

| File | Vai trò |
|---|---|
| `Sources/AppMain.swift` | Entry point, `AppDelegate`, menu bar status item, popover |
| `Sources/Views.swift` | Toàn bộ UI SwiftUI (main popover, settings, pin, display, thermal) |
| `Sources/WindowManager.swift` | AltTab: liệt kê cửa sổ AX/CG, HUD, MRU, chụp thumbnail nền |
| `Sources/WindowSnapManager.swift` | Chia cửa sổ & chuyển màn hình |
| `Sources/KeyInterceptor.swift` | CGEventTap toàn cục: phím tắt, media keys, clipboard HUD keys |
| `Sources/ClipboardManager.swift` | Lịch sử clipboard, giới hạn lưu, retention, HUD panel |
| `Sources/ClipboardOverlayView.swift` | UI bảng Clipboard HUD |
| `Sources/AltTabOverlayView.swift` | UI HUD AltTab |
| `Sources/ThermalManager.swift` | Đọc nhiệt độ HID/PMU + trạng thái thermal (KHÔNG điều khiển quạt) |
| `Sources/BatteryManager.swift` | Khóa sạc 80%, helper SMC |
| `Sources/DisplayManager.swift` | Độ sáng, DDC/CI, màn hình ảo |
| `Sources/VirtualDisplayManager.swift` + `VirtualDisplayBridge/` | Cầu nối Objective-C cho màn hình ảo |
| `Sources/CaffeinateManager.swift` | Chống sleep màn hình |
| `Sources/UpdateManager.swift` | Kiểm tra/tải bản cập nhật từ `version.json` trên GitHub |
| `Sources/ShellHelper.swift` | `shell()` đồng bộ + tìm binary Homebrew |

## 4. Quy ước

- UI và log dùng **tiếng Việt**; tên biến/hàm dùng tiếng Anh.
- `@MainActor` cho các manager; cập nhật state UI phải trên main thread.
- Tránh chạy `Process`/`shell()` nặng trên main thread (gây khựng popover).
- Lưu cài đặt qua `UserDefaults` với key có tiền tố rõ ràng (`clipboard_*`, `fan_*` cũ đã bỏ, `show_menubar_thermal`…).
- Không hardcode đường dẫn tuyệt đối của máy dev (ví dụ `/Users/khacdai24/...`).
- Giữ `Package.swift` ở `swift-tools-version: 5.9` (Swift 5 language mode) để tránh lỗi concurrency nghiêm ngặt.

## 5. Thay đổi v1.5.2 (2026-10-28)

### 5.1. AltTab hết delay ~0.5s
- `WindowManager.refreshWindows()` **không còn chụp thumbnail đồng bộ**; `thumbnail = nil` khi dựng danh sách.
- `beginThumbnailCapture()` chụp ảnh nền bằng `DispatchQueue.global(qos: .userInitiated)`, cập nhật UI trên main; có `thumbnailGeneration` để huỷ khi HUD đóng.
- HUD được hiện ngay sau khi liệt kê cửa sổ; ảnh xem trước xuất hiện dần.
- Giảm `AXUIElementSetMessagingTimeout` từ `0.1` → `0.05`.
- `showOverlay()` tái sử dụng `NSHostingController` (không tạo mới mỗi lần).
- Thêm `handleModifierReleased()`; `KeyInterceptor` gọi hàm này khi nhả `⌘/⌥`.
- `handleShortcut()` reset `isModifierHeld`/`gIsAltTabVisible` nếu danh sách cửa sổ rỗng.

### 5.2. Clipboard: giới hạn lưu & dọn dẹp
- `ClipboardManager.maxItemsCount`: `0` = **không giới hạn**; hỗ trợ 50/100/200/500/∞.
- Thêm `autoCleanupDays` (UserDefaults key `clipboard_auto_cleanup_days`): `0/7/30/90` ngày.
- `applyRetentionPolicy()` tự xoá mục **chưa ghim** cũ hơn số ngày cấu hình; chạy khi khởi động, khi thêm clip và khi đổi cài đặt.
- `cleanupNow()` cho nút "Dọn ngay": trả về số mục đã xoá và hiện `cleanupMessage` (tự ẩn sau 3.5s). Trước đây bấm không có phản hồi nên trông như "không dọn" — thực chất chỉ xoá mục cũ hơn 30 ngày mà lịch sử toàn mục mới.
- `requestClearAllUnpinned()` cho nút "Xoá tất cả": xoá mọi mục chưa ghim, cần bấm 2 lần (`pendingClearAllConfirm`, tự huỷ sau 4s).
- `trimItems()` xử lý đúng trường hợp không giới hạn; luôn giữ mục đã ghim.
- UI mới trong `Views.swift`: hàng chip giới hạn, hàng "Tự động xoá", 2 nút "Dọn ngay" / "Xoá tất cả", dòng thông báo kết quả, cảnh báo khi chọn ∞.

### 5.3. Phím tắt Clipboard HUD
- `KeyInterceptor.swift` xử lý khi `gIsClipboardHUDVisible`:
  - `1–9` → `pasteItemAt(index:)` (chỉ khi ô tìm kiếm đang rỗng, cờ `gIsClipboardSearchEmpty`).
  - `↑/↓` → `selectPrevious()/selectNext()`.
  - `↵`/numpad Enter → `pasteSelectedItem()`.
  - `⌥P` → `togglePinSelected()`; `⌥⌫` → `deleteSelectedItem()`; `⎋` → đóng.
- `ClipboardManager` thêm `selectedItem`, `clampSelection()`, `selectNext/Previous`, `pasteSelectedItem`, `pasteItemAt`, `togglePinSelected`, `deleteSelectedItem`.
- `⌘`/`⌃` được thả qua để không phá shortcut hệ thống.
- `ClipboardOverlayView` Enter dùng mục đang chọn (không còn luôn dán mục đầu).

### 5.4. Cỡ chữ phím tắt
- `ClipboardOverlayView.legendItem`: 7.5 → 9.5/9.
- `AltTabOverlayView.HintChip`: 8 → 9.5.
- `Views.swift` `shortcutPill`: 8 → 9.5/9.

### 5.5. Gỡ Fan Control
- Xoá toàn bộ `activeFanControlCard`, 4 chế độ quạt, slider RPM, Smart Curve, preset RPM trong `Views.swift`.
- `ThermalManager.swift` viết lại: chỉ còn đọc nhiệt độ HID/PMU, trạng thái thermal, pill nhiệt độ Menu Bar. Đã xoá `FanControlMode`, `ThermalSensorTarget`, `FanModel`, `detectFans`, `applyActiveFanProfile`, `restoreFansToAuto`.
- `AppMain.applicationWillTerminate` không còn gọi `restoreFansToAuto()`.
- `menuBarDisplayMode` bị bỏ; Menu Bar chỉ hiện `44°C`.
- Tab "Quạt & Nhiệt độ" đổi thành **"Nhiệt độ & Cảm biến"**.

### 5.6. Phiên bản & tài liệu
- Bump `1.5.1` → `1.5.2` tại: `build.sh`, `Sources/UpdateManager.swift`, `version.json`, badge/README.
- Thêm changelog v1.5.2 trong `README.md`.
- Cần tạo tag `v1.5.2` và push để GitHub Actions tạo release khớp `version.json`.

## 6. Chứng chỉ ký cố định (bắt buộc cho TCC)

**Vấn đề:** ký ad-hoc (`codesign -s -`) khiến cdhash đổi sau mỗi lần build →
macOS coi là app khác → **thu hồi quyền Accessibility** → `⌘Tab`, `⌘⇧C` không chạy
cho tới khi người dùng cấp lại tay.

**Giải pháp đã áp dụng:** chứng chỉ self-signed cố định `HyperMac Self-Signed`.

```bash
./scripts/setup-signing-identity.sh   # chạy 1 lần
./build.sh                            # build.sh tự dùng identity này
```

- Script sinh key + cert (EKU `codeSigning`) trong `~/.hypermac-signing/` (mode 700),
  import vào login keychain, rồi thêm trust policy Code Signing ở user domain.
- `build.sh` tự dò identity; nếu có thì ký bằng nó, nếu không thì fallback ad-hoc
  (kèm cảnh báo). Có thể override bằng biến môi trường `HYPERMAC_SIGN_IDENTITY`.
- Designated Requirement hiện tại (`codesign -d -r-`):
  `identifier "com.opensource.hypermac" and certificate root = H"5f052de8…"`
  → **không phụ thuộc nội dung binary**, nên quyền TCC giữ nguyên qua mọi rebuild.

**Nếu vẫn mất quyền / app không nhận phím tắt:**

```bash
# 1. Kiểm tra chữ ký
codesign -dv --verbose=4 /Applications/HyperMac.app | grep Authority
# 2. Xoá entry TCC cũ rồi mở lại app để prompt
tccutil reset Accessibility com.opensource.hypermac
open /Applications/HyperMac.app
# 3. System Settings → Privacy & Security → Accessibility → bật HyperMac
```

**Không commit** `~/.hypermac-signing/` hay file `.p12` vào repo (chứa private key).

## 7. Ghi chú kiểm thử

- Máy test hiện tại: `Mac14,2` (MacBook Air M2, fanless), macOS 26.6.
- `Resources/smc -f` trả `Total fans in system: 0` — bình thường với máy không quạt.
- Kiểm tra nhanh sau khi sửa:
  1. `⌘ + Tab` phải hiện HUD gần như tức thì (< ~100ms), thumbnail xuất hiện sau.
  2. `⌘ + ⇧ + C` mở Clipboard; thử `1–9`, `↑↓`, `↵`, `⌥P`, `⌥⌫`, `⎋`.
  3. Settings → Clipboard: chọn 500/∞, đổi "Tự động xoá", bấm "Dọn ngay".
  4. Tab nhiệt độ: không còn bảng quạt; chỉ có nhiệt độ, cảm biến, pill Menu Bar.
