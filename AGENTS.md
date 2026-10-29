# AGENTS.md — HyperMac (DisplayControl)

> Tài liệu dành cho AI coding agent (Antigravity IDE, OpenCode, Cursor, Claude Code…) đọc trước khi chỉnh sửa dự án. Cập nhật lần cuối: **2026-10-29 (v1.6.0)**.

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
| `Sources/AccessibilityRecovery.swift` | Tự reset + prompt lại quyền Accessibility sau update |
| `Sources/ClipboardManager.swift` | Lịch sử clipboard, giới hạn lưu, retention, HUD panel |
| `Sources/ClipboardOverlayView.swift` | UI bảng Clipboard HUD |
| `Sources/AltTabOverlayView.swift` | UI HUD AltTab |
| `Sources/ThermalManager.swift` | Đọc nhiệt độ HID/PMU + trạng thái thermal (KHÔNG điều khiển quạt) |
| `Sources/DiskSpeedManager.swift` | Đo tốc độ đọc/ghi ổ vật lý (IOKit), interface LAN cho NAS, I/O theo tiến trình |
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
- **Không tự tạo tag/release hay push bản phát hành** khi chưa được người dùng xác nhận rõ ràng. Cứ build local, test xong, chờ lệnh.

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

## 6. Thay đổi v1.6.0 (2026-10-28)

### 6.1. Đo tốc độ chép file — `Sources/DiskSpeedManager.swift`
- UI: `FileTransferSpeedCard` trong `HardwareCareTabView`, đặt ngay dưới thanh chọn
  Pin / Nhiệt độ (luôn hiển thị, không phụ thuộc segment đang chọn).
- **Mặc định TẮT**: người dùng bật bằng switch trên card (lưu ở
  `UserDefaults["disk_speed_enabled"]`). Khi tắt, không có timer, không quét ổ/tiến
  trình, không cấp phát bộ đếm.
- **Chỉ chạy khi popover mở**: `AppDelegate` là `NSPopoverDelegate`; `popoverDidShow`
  → `setPopoverVisible(true)`, `popoverDidClose` → `setPopoverVisible(false)`.
  Đóng bảng là dừng timer + `sampler.reset()` + xoá số liệu đã publish.
- Kiến trúc: `DiskSpeedManager` (`@MainActor`, `ObservableObject`) giữ `Timer` 1s trên
  main run loop; mỗi tick đẩy `DiskSpeedSampler.sample()` sang `DispatchQueue` nền.
  Sampler tính delta byte / delta thời gian (`max(0.25s, …)`) → MB/s.

**Ổ vật lý (chính xác):**
- Duyệt `IOMedia` có `Whole = true`, lấy **cha trực tiếp**; chỉ nhận khi class cha là
  `IOBlockStorageDriver` (nơi có property `Statistics`).
- `AppleAPFSContainerScheme` cũng có `Statistics` riêng → nếu không lọc theo class
  cha, tốc độ sẽ bị cộng trùng (gấp đôi) giữa `disk0` và `disk3`.
- Bỏ qua media ảo của file `.dmg/.iso` (IORegistry name chứa `Disk Image`) để ổ
  "Tor Browser"… không xuất hiện như ổ cứng thật.
- Tên hiển thị: đi ngược cây IORegistry từ volume đang mount (`getmntinfo`) lên tới
  IOMedia vật lý (`mediaEntry(forBSDName:)`), chọn volume gốc `/` hoặc volume lớn
  nhất. Fallback: `Device Characteristics → Product Name` (`APPLE SSD…` →
  `SSD nội bộ`), cuối cùng là BSD name.
- Dòng chi tiết trong card hiển thị **nguồn → đích** (ổ đọc nhiều nhất → ổ ghi nhiều
  nhất), ví dụ `U280-Pro → SSD nội bộ`; nếu cùng một ổ thì chỉ hiện tên ổ.

**NAS / ổ mạng (xấp xỉ):**
- `networkVolumeHosts()` lấy host từ `getmntinfo` (`//user@host/share`, `host:/path`).
- `route -n get <host>` (cache 60s) → tên interface (`en0`, `en1`, …).
- Đọc byte counter 64-bit của interface qua `sysctl` MIB
  `[CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]` (`if_msghdr2.ifm_data`).
- Nếu không resolve được interface: cộng các interface `en*`/`ppp*`.
- Đây là tốc độ **của card mạng**, không phải riêng phiên SMB → có thể lẫn traffic khác.

**Tiến trình đang chép:**
- `proc_listallpids` + `proc_pid_rusage(pid, RUSAGE_INFO_V4)` lấy
  `ri_diskio_bytesread/written`; lưu counter của frame trước để tính delta.
- Chỉ gắn tên tiến trình khi `peak >= 3 MB/s` **và** `peak >= 50%` tổng lưu lượng,
  nếu không sẽ hiện nhầm I/O nền (Spotlight, `BackgroundShortcutRunner`).
- Hạn chế đã biết: ghi qua page cache có thể xong trước nhịp lấy mẫu nên tiến trình
  có thể không hiện (ví dụ `dd` tốc độ cao); số liệu ổ cứng vẫn đúng.

**Debug:** đặt `HYPERMAC_DISKSPEED_DEBUG=1` để log mỗi mẫu vào `/tmp/displaycontrol.log`
(dòng `💾 DiskSpeed: …`). Hook `HYPERMAC_DISKSPEED_TEST_HOST` đã được gỡ.

### 6.2. Kiểm thử giao diện không cần chụp màn hình
- `HYPERMAC_PREVIEW=1` mở cửa sổ 380×570 chứa `MainView` (không tạo status item).
- `HYPERMAC_PREVIEW_TAB=0|1|2` chọn tab (mặc định 1).
- `HYPERMAC_PREVIEW_OUT=/tmp/ui.png` render thẳng ra PNG bằng `ImageRenderer`
  rồi thoát — hữu ích khi terminal không có quyền Screen Recording.
- `HYPERMAC_DISKSPEED_FAKE=1` nạp số liệu giả (U280-Pro → SSD, LAN en0) để kiểm tra
  layout dòng chi tiết. **Chỉ dùng khi phát triển**, không ảnh hưởng người dùng.
- `HYPERMAC_DISKSPEED_AUTOSTART=1` giả lập popover đang mở lúc khởi động;
  `HYPERMAC_DISKSPEED_AUTOCLOSE=<giây>` tự đóng sau N giây — dùng để kiểm tra
  timer bật/tắt mà không cần bấm menu bar.
- Lưu ý: `ImageRenderer` không render nội dung bên trong `ScrollView`, nên ảnh
  preview chỉ dùng để kiểm tra phần header/tab/card, không thay thế kiểm thử thật.

### 6.3. Phiên bản & tài liệu
- Bump `1.5.2` → `1.6.0` tại: `build.sh`, `Sources/UpdateManager.swift`, `version.json`,
  badge + nút tải trong `README.md`.
- Thêm changelog v1.6.0 trong `README.md`.
- Cần tạo tag `v1.6.0` và push để GitHub Actions tạo release khớp `version.json`.

## 7. Chứng chỉ ký cố định (bắt buộc cho TCC)

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
`.gitignore` đã chặn `*.p12` và `*.p12.base64`.

### 7.1. Ký bản phát hành trên GitHub Actions

Runner không có keychain của máy dev, nên phải đưa private key vào **GitHub Secrets**:

1. Xuất chứng chỉ (giữ nguyên key/cert cũ để root hash không đổi):

```bash
./scripts/export-ci-signing.sh
# → ~/.hypermac-signing/ci-signing.p12
# → ~/.hypermac-signing/ci-signing.p12.base64
# → in ra mật khẩu + certificate root SHA-1
```

2. Thêm 2 secret tại `Settings → Secrets and variables → Actions`:
   - `HYPERMAC_SIGNING_P12_BASE64`: nội dung file `.base64`
   - `HYPERMAC_SIGNING_P12_PASSWORD`: mật khẩu script in ra

3. Workflow `.github/workflows/release.yml` sẽ:
   - tạo keychain tạm, import `.p12`, mở partition list cho `codesign`,
   - build với `HYPERMAC_SIGN_IDENTITY=HyperMac Self-Signed` và
     `HYPERMAC_SIGN_KEYCHAIN=<keychain tạm>` (build.sh truyền `--keychain` cho
     `codesign`, **không đụng vào search list keychain của runner**),
   - verify `Authority=HyperMac Self-Signed` + in DR,
   - xoá keychain tạm ở bước `always()`.

Nếu thiếu secret, workflow vẫn build nhưng **fallback ad-hoc** (kèm cảnh báo) —
khi đó quyền Accessibility sẽ mất sau update.

**Lưu ý quan trọng:**
- Chỉ cần **một lần** chuyển từ bản ad-hoc cũ (≤1.5.2) sang bản ký cert: TCC đổi
  DR nên quyền mất một lần; từ các bản sau thì giữ nguyên.
- Không bao giờ tạo lại cert/key (root hash đổi → mất quyền của mọi người).
  Cert hiện có hạn 10 năm (`-days 3650`).
- Secret chứa private key: nếu repo bị xâm nhập, key có thể bị lộ → phải tạo cert
  mới và chấp nhận mất quyền một lần.

### 7.2. Tự khôi phục quyền sau update — `Sources/AccessibilityRecovery.swift`

- Gọi trong `applicationDidFinishLaunching` **trước** `KeyInterceptor.shared.start()`.
- Mỗi lần khởi động, nếu `AXIsProcessTrusted() == false` **và**
  `UserDefaults["ax_recovery_version"] != phiên bản hiện tại`:
  - chạy `tccutil reset Accessibility com.opensource.hypermac` (xoá entry cũ bị kẹt),
  - lưu `ax_recovery_version` = phiên bản hiện tại (mỗi bản chỉ reset **một lần**,
    nên không lặp lại mỗi lần mở app và không phiền người dùng đã từ chối cấp quyền),
  - sau 0.8s gọi `AXIsProcessTrustedWithOptions(prompt: true)` để macOS hiện hộp
    thoại cấp lại.
- Không cần cờ "từng được cấp quyền": entry TCC bị kẹt sau update thường vẫn hiện
  trong System Settings nên không thể phân biệt bằng `UserDefaults`.
- Người dùng chỉ cần bật switch trong System Settings, **không phải xoá app và thêm lại**.
- `tccutil` chỉ reset được khi app có bundle ID hợp lệ; nếu không có, hàm bỏ qua im lặng.


## 8. Ghi chú kiểm thử

- Máy test hiện tại: `Mac14,2` (MacBook Air M2, fanless), macOS 26.6.
- `Resources/smc -f` trả `Total fans in system: 0` — bình thường với máy không quạt.
- Kiểm tra nhanh sau khi sửa:
  1. `⌘ + Tab` phải hiện HUD gần như tức thì (< ~100ms), thumbnail xuất hiện sau.
  2. `⌘ + ⇧ + C` mở Clipboard; thử `1–9`, `↑↓`, `↵`, `⌥P`, `⌥⌫`, `⎋`.
  3. Settings → Clipboard: chọn 500/∞, đổi "Tự động xoá", bấm "Dọn ngay".
  4. Tab nhiệt độ: không còn bảng quạt; chỉ có nhiệt độ, cảm biến, pill Menu Bar.
  5. Ô **Chép file** (tab Pin & Phần cứng): chạy `dd if=/dev/zero of=/tmp/dstest.bin bs=1m count=600`
     → số `↑` phải nhảy lên hàng trăm MB/s và tên ổ là `Macintosh HD` / `SSD nội bộ`;
     chép thẻ nhớ → ổ rời phải thấy tên volume của cả hai ổ trong tooltip.
  6. NAS: mount SMB rồi chép file; chip mạng hiện `LAN enX` với tốc độ tương đương
     lưu lượng thực (đối chiếu `netstat -ibn` trước/sau khi chép).
