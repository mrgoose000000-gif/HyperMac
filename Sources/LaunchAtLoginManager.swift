import Foundation
import AppKit
import ServiceManagement

@MainActor
public class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public var isEnabled: Bool = false

    private init() {
        // Read cached preference first for instant UI response
        if UserDefaults.standard.object(forKey: "launch_at_login_enabled") != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: "launch_at_login_enabled")
        }
        // Check actual system state in background
        checkSystemStatus()
    }

    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "launch_at_login_enabled")

        let appPath = Self.currentAppPath

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if enabled {
                Self.registerLaunchAtLogin(appPath: appPath)
            } else {
                Self.unregisterLaunchAtLogin()
            }

            // Verify final status
            let actualStatus = Self.isSystemLaunchAtLoginActive(appPath: appPath)
            DispatchQueue.main.async {
                self?.isEnabled = actualStatus
                UserDefaults.standard.set(actualStatus, forKey: "launch_at_login_enabled")
            }
        }
    }

    public func checkSystemStatus() {
        let appPath = Self.currentAppPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let active = Self.isSystemLaunchAtLoginActive(appPath: appPath)
            DispatchQueue.main.async {
                self?.isEnabled = active
                UserDefaults.standard.set(active, forKey: "launch_at_login_enabled")
            }
        }
    }

    private static var currentAppPath: String {
        let path = Bundle.main.bundleURL.path
        if path.hasSuffix(".app") {
            return path
        }
        return "/Applications/HyperMac.app"
    }

    // MARK: - System Registration (SMAppService + System Events Fallback)

    nonisolated private static func registerLaunchAtLogin(appPath: String) {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } catch {
                appLog("⚠️ SMAppService register note: \(error.localizedDescription)")
            }
        }

        // Always ensure presence in System Events login items for complete launch reliability
        let script = """
        tell application "System Events"
            if not (exists (first login item whose name is "HyperMac")) then
                make login item at end with properties {path:"\(appPath)", hidden:false, name:"HyperMac"}
            end if
        end tell
        """
        runAppleScript(script)
    }

    nonisolated private static func unregisterLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                appLog("⚠️ SMAppService unregister note: \(error.localizedDescription)")
            }
        }

        let script = """
        tell application "System Events"
            delete (every login item whose name is "HyperMac")
        end tell
        """
        runAppleScript(script)
    }

    nonisolated private static func isSystemLaunchAtLoginActive(appPath: String) -> Bool {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                return true
            }
        }

        let script = """
        tell application "System Events"
            return exists (first login item whose name is "HyperMac")
        end tell
        """
        let result = runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result == "true"
    }

    @discardableResult
    nonisolated private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let output = scriptObject.executeAndReturnError(&error)
            if let err = error {
                appLog("⚠️ AppleScript note: \(err)")
                return nil
            }
            return output.stringValue
        }
        return nil
    }
}

