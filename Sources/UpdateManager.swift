import Foundation
import AppKit
import Combine

// MARK: - Update Status States

public enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(version: String, notes: String, downloadUrl: URL?, htmlUrl: URL?)
    case downloading(progress: Double)
    case extracting
    case readyToRestart
    case failed(String)
}

// MARK: - GitHub Release API Models

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
    }
}

struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadUrl: String
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

struct VersionManifest: Decodable {
    let version: String
    let name: String?
    let notes: String?
    let downloadUrl: String?
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case version
        case name
        case notes
        case downloadUrl = "download_url"
        case htmlUrl = "html_url"
    }
}

// MARK: - Update Manager

@MainActor
public class UpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = UpdateManager()

    public static let currentVersion: String = "1.5.2"

    @Published public var state: UpdateState = .idle
    @Published public var downloadProgress: Double = 0.0
    @Published public var showUpdateModal: Bool = false
    @Published public var hasNewUpdate: Bool = false
    @Published public var latestVersionString: String = ""
    @Published public var releaseNotes: String = ""
    @Published public var autoCheckEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: "hypermac_auto_check_updates")
        }
    }

    private var activeDownloadTask: URLSessionDownloadTask?
    private var downloadUrl: URL?
    private var htmlUrl: URL?

    public override init() {
        super.init()
        if UserDefaults.standard.object(forKey: "hypermac_auto_check_updates") != nil {
            self.autoCheckEnabled = UserDefaults.standard.bool(forKey: "hypermac_auto_check_updates")
        } else {
            self.autoCheckEnabled = true
        }

        // Silent background update check after 3 seconds on launch
        if autoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.checkForUpdates(silent: true)
            }
        }
    }

    // MARK: - Version Comparison

    public static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n"))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n"))

        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }

    // MARK: - Check For Updates

    public func checkForUpdates(silent: Bool = false) {
        if !silent {
            self.showUpdateModal = true
        }
        self.state = .checking

        Task {
            var lastStatusCode: Int = 0
            // Kết quả "đã mới nhất" từ GitHub API, dùng dự phòng nếu manifest lỗi.
            var apiUpToDate: (ver: String, notes: String, dl: URL?, html: URL?)? = nil

            // Attempt 1: Standard GitHub Releases API
            let releaseUrl = URL(string: "https://api.github.com/repos/mrgoose000000-gif/HyperMac/releases/latest")!
            var request = URLRequest(url: releaseUrl)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("HyperMac-App", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 8.0

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResp = response as? HTTPURLResponse {
                    lastStatusCode = httpResp.statusCode
                    if httpResp.statusCode == 200 {
                        let decoder = JSONDecoder()
                        let release = try decoder.decode(GitHubRelease.self, from: data)

                        let tagVer = release.tagName
                        let notes = release.body ?? release.name ?? "Bản cập nhật mới dành cho HyperMac."
                        let releasePage = URL(string: release.htmlUrl)

                        // Find zip asset
                        let zipAsset = release.assets.first(where: {
                            $0.name.lowercased().hasSuffix(".zip") || $0.name.lowercased().contains("hypermac")
                        })
                        let dlUrl = zipAsset.flatMap { URL(string: $0.browserDownloadUrl) }

                        if Self.isVersion(tagVer, greaterThan: Self.currentVersion) {
                            self.handleDiscoveredVersion(
                                latestVer: tagVer,
                                notes: notes,
                                downloadUrl: dlUrl,
                                htmlUrl: releasePage,
                                silent: silent
                            )
                            return
                        }

                        // Release mới nhất chưa cao hơn bản đang chạy: vẫn thử manifest
                        // để không bỏ lỡ trường hợp release tạo chậm hơn / thiếu asset.
                        apiUpToDate = (tagVer, notes, dlUrl, releasePage)
                    }
                }
            } catch {
                appLog("⚠️ GitHub API check failed: \(error.localizedDescription), trying raw fallback...")
            }

            // Attempt 2: Fast raw manifest fallback (raw.githubusercontent.com - no rate limits)
            let manifestUrl = URL(string: "https://raw.githubusercontent.com/mrgoose000000-gif/HyperMac/main/version.json")!
            var manifestReq = URLRequest(url: manifestUrl)
            manifestReq.cachePolicy = .reloadIgnoringLocalCacheData
            manifestReq.timeoutInterval = 8.0

            do {
                let (mData, mResp) = try await URLSession.shared.data(for: manifestReq)
                if let httpResp = mResp as? HTTPURLResponse {
                    lastStatusCode = httpResp.statusCode
                    if httpResp.statusCode == 200 {
                        let decoder = JSONDecoder()
                        let manifest = try decoder.decode(VersionManifest.self, from: mData)

                        let dlUrl = manifest.downloadUrl.flatMap { URL(string: $0) }
                        let pageUrl = manifest.htmlUrl.flatMap { URL(string: $0) } ?? URL(string: "https://github.com/mrgoose000000-gif/HyperMac/releases")
                        let notes = manifest.notes ?? manifest.name ?? "Bản cập nhật mới dành cho HyperMac."

                        self.handleDiscoveredVersion(
                            latestVer: manifest.version,
                            notes: notes,
                            downloadUrl: dlUrl,
                            htmlUrl: pageUrl,
                            silent: silent
                        )
                        return
                    }
                }
            } catch {
                appLog("⚠️ Raw manifest check failed: \(error.localizedDescription)")
            }

            // Manifest không dùng được nhưng API nói đã mới nhất → báo đã mới nhất.
            if let api = apiUpToDate {
                self.handleDiscoveredVersion(
                    latestVer: api.ver,
                    notes: api.notes,
                    downloadUrl: api.dl,
                    htmlUrl: api.html,
                    silent: silent
                )
                return
            }

            // If both failed
            if !silent {
                if lastStatusCode == 404 {
                    self.state = .failed("Kho lưu trữ GitHub đang ở chế độ Riêng tư (Private) hoặc chưa có Release công khai (Mã lỗi 404).")
                } else if lastStatusCode == 403 {
                    self.state = .failed("Bị giới hạn tần suất truy vấn từ GitHub API (Mã lỗi 403). Vui lòng thử lại sau ít phút.")
                } else {
                    self.state = .failed("Không thể kết nối đến máy chủ GitHub. Vui lòng kiểm tra lại kết nối mạng.")
                }
            } else {
                self.state = .idle
            }
        }
    }

    private func handleDiscoveredVersion(
        latestVer: String,
        notes: String,
        downloadUrl: URL?,
        htmlUrl: URL?,
        silent: Bool
    ) {
        self.latestVersionString = latestVer
        self.releaseNotes = notes
        self.downloadUrl = downloadUrl
        self.htmlUrl = htmlUrl

        if Self.isVersion(latestVer, greaterThan: Self.currentVersion) {
            self.hasNewUpdate = true
            self.state = .updateAvailable(
                version: latestVer,
                notes: notes,
                downloadUrl: downloadUrl,
                htmlUrl: htmlUrl
            )
            if !silent {
                self.showUpdateModal = true
            }
            appLog("✨ UpdateManager: New update available: \(latestVer) (Current: \(Self.currentVersion))")
        } else {
            self.hasNewUpdate = false
            self.state = .upToDate(version: Self.currentVersion)
            appLog("✅ UpdateManager: Already up to date: \(Self.currentVersion)")
        }
    }

    // MARK: - Download & Automatic Installation

    public func startUpdate() {
        guard let url = downloadUrl else {
            // If no direct binary asset attached, open GitHub release page
            if let html = htmlUrl ?? URL(string: "https://github.com/mrgoose000000-gif/HyperMac/releases") {
                NSWorkspace.shared.open(html)
            }
            return
        }

        self.state = .downloading(progress: 0.0)
        self.downloadProgress = 0.0

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        let task = session.downloadTask(with: url)
        self.activeDownloadTask = task
        task.resume()
        appLog("🚀 UpdateManager: Downloading update from \(url)")
    }

    public func openReleasePage() {
        if let url = htmlUrl ?? URL(string: "https://github.com/mrgoose000000-gif/HyperMac/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor in
                self.downloadProgress = progress
                self.state = .downloading(progress: progress)
            }
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else {
            Task { @MainActor in
                self.state = .failed("Máy chủ GitHub trả về mã lỗi \(status). Bản cập nhật chưa được tải, app hiện tại vẫn nguyên vẹn.")
            }
            return
        }

        let tempZip = URL(fileURLWithPath: "/tmp/HyperMac_update.zip")
        try? FileManager.default.removeItem(at: tempZip)

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            // HTML error page / empty file would be a few KB at most.
            guard size > 100_000 else {
                Task { @MainActor in
                    self.state = .failed("Tệp cập nhật tải về không hợp lệ (\(size / 1024) KB). Có thể Release chưa đính kèm HyperMac.zip.")
                }
                return
            }

            try FileManager.default.moveItem(at: location, to: tempZip)
            Task { @MainActor in
                self.state = .extracting
                self.stageAndInstall(zipPath: tempZip.path)
            }
        } catch {
            Task { @MainActor in
                self.state = .failed("Lỗi lưu file cập nhật: \(error.localizedDescription)")
            }
        }
    }

    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.state = .failed("Lỗi tải bản cập nhật: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Stage & Validate (KHÔNG đụng vào app đang chạy)

    /// Giải nén + kiểm tra gói cập nhật TRƯỚC khi thoát app.
    /// Nếu zip hỏng/không phải HyperMac, app đang chạy vẫn nguyên vẹn.
    private func stageAndInstall(zipPath: String) {
        let staging = "/tmp/HyperMac_staging"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            try? fm.removeItem(atPath: staging)
            try? fm.createDirectory(atPath: staging, withIntermediateDirectories: true)

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zipPath, staging]
            ditto.standardOutput = FileHandle.nullDevice
            ditto.standardError = FileHandle.nullDevice

            var extractOK = false
            do {
                try ditto.run()
                ditto.waitUntilExit()
                extractOK = ditto.terminationStatus == 0
            } catch {
                extractOK = false
            }

            guard extractOK else {
                DispatchQueue.main.async {
                    self?.state = .failed("Tệp cập nhật bị hỏng hoặc không phải ZIP hợp lệ. App hiện tại không bị ảnh hưởng.")
                }
                return
            }

            let appPath = staging + "/HyperMac.app"
            let binaryPath = appPath + "/Contents/MacOS/HyperMac"
            let bundleID = Bundle(path: appPath)?.bundleIdentifier

            guard fm.fileExists(atPath: binaryPath), bundleID == "com.opensource.hypermac" else {
                DispatchQueue.main.async {
                    self?.state = .failed("Gói cập nhật không chứa HyperMac.app hợp lệ. App hiện tại không bị ảnh hưởng.")
                }
                return
            }

            DispatchQueue.main.async {
                self?.performInPlaceUpdate(stagedAppPath: appPath, zipPath: zipPath)
            }
        }
    }

    // MARK: - In-Place Atomic Replacement & Relaunch

    private func performInPlaceUpdate(stagedAppPath: String, zipPath: String) {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let updaterScriptPath = "/tmp/hypermac_in_place_updater.sh"

        let appPath = "/Applications/HyperMac.app"
        let newPath = "/Applications/.HyperMac.new"
        let backupPath = "/Applications/.HyperMac.bak"

        let script = """
        #!/bin/bash
        exec > /tmp/hypermac_updater.log 2>&1

        echo "🔄 HyperMac Updater started for PID \(currentPid)..."
        PID="\(currentPid)"
        APP="\(appPath)"
        NEW="\(newPath)"
        BAK="\(backupPath)"
        STAGED="\(stagedAppPath)"

        # 1. Chờ app thoát hẳn
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        sleep 0.4
        echo "🛑 Current instance exited."

        # 2. Copy sang thư mục tạm cạnh app (cùng volume → mv là atomic)
        rm -rf "$NEW"
        if ! cp -R "$STAGED" "$NEW"; then
            echo "❌ cp thất bại, giữ nguyên app cũ."
            rm -rf "$NEW"
            open "$APP"
            exit 1
        fi
        if [ ! -x "$NEW/Contents/MacOS/HyperMac" ]; then
            echo "❌ Binary không tồn tại, giữ nguyên app cũ."
            rm -rf "$NEW"
            open "$APP"
            exit 1
        fi
        xattr -cr "$NEW" 2>/dev/null || true

        # 3. Đổi chỗ có backup để rollback nếu lỗi
        rm -rf "$BAK"
        if [ -d "$APP" ]; then mv "$APP" "$BAK"; fi
        if mv "$NEW" "$APP"; then
            echo "✅ Đã cài bản mới."
            open "$APP"
            sleep 4
            rm -rf "$BAK"
        else
            echo "❌ mv thất bại, rollback."
            rm -rf "$APP"
            if [ -d "$BAK" ]; then mv "$BAK" "$APP"; fi
            open "$APP"
        fi

        # 4. Dọn dẹp
        rm -rf "$STAGED" "\(zipPath)" "\(updaterScriptPath)"
        echo "✅ Update complete."
        """

        do {
            try script.write(toFile: updaterScriptPath, atomically: true, encoding: .utf8)
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", updaterScriptPath]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()

            // Run updater in background
            let updateProcess = Process()
            updateProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            updateProcess.arguments = [updaterScriptPath]
            try updateProcess.run()

            self.state = .readyToRestart
            appLog("✨ UpdateManager: Updater script launched. Quitting current application...")

            // Quit application so updater script proceeds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            self.state = .failed("Không thể khởi động tiến trình cập nhật: \(error.localizedDescription)")
        }
    }
}
