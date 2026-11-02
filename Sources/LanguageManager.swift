import SwiftUI
import AppKit
import Combine

// MARK: - App Language Enum
public enum AppLanguage: String, CaseIterable, Identifiable {
    case vi = "vi"
    case en = "en"

    public var id: String { rawValue }

    public var code: String { rawValue }

    public var displayName: String {
        switch self {
        case .vi: return "Tiếng Việt"
        case .en: return "English"
        }
    }
}

// MARK: - Language Manager
public class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()

    private let storageKey = "hypermac_app_language"

    @Published public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: storageKey)
        }
    }

    @Published public var showConfirmDialog: Bool = false

    private init() {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = .vi
        }
    }

    public var nextLanguage: AppLanguage {
        currentLanguage == .vi ? .en : .vi
    }

    public func switchLanguage(to language: AppLanguage) {
        currentLanguage = language
    }

    public func toggleLanguage() {
        currentLanguage = nextLanguage
    }

    /// Shows a native macOS confirmation alert before switching language.
    public func promptLanguageSwitch() {
        let toEnglish = currentLanguage == .vi
        let alert = NSAlert()
        alert.messageText = toEnglish ? "Chuyển sang Tiếng Anh?" : "Switch to Vietnamese?"
        alert.informativeText = toEnglish
            ? "Bạn có chắc chắn muốn chuyển ngôn ngữ hiển thị sang Tiếng Anh (English) không?"
            : "Do you want to switch the interface display language to Tiếng Việt (Vietnamese)?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: toEnglish ? "Chuyển sang English" : "Chuyển sang Tiếng Việt")
        alert.addButton(withTitle: toEnglish ? "Huỷ" : "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            switchLanguage(to: toEnglish ? .en : .vi)
        }
    }
}

// MARK: - Global Localization Helper
/// Returns Vietnamese or English string depending on the active language setting.
@inline(__always)
public func tr(_ vi: String, _ en: String) -> String {
    LanguageManager.shared.currentLanguage == .en ? en : vi
}
