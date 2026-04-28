import Foundation
import AppKit
import Combine

final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var fullDiskAccessGranted = false

    private var hasAutoOpenedSettingsThisLaunch = false

    private init() {
        refreshFullDiskAccess()
    }

    func refreshFullDiskAccess() {
        fullDiskAccessGranted = Self.detectFullDiskAccess()
    }

    func autoPromptForFullDiskAccessIfNeeded() {
        refreshFullDiskAccess()
        guard !fullDiskAccessGranted, !hasAutoOpenedSettingsThisLaunch else { return }
        hasAutoOpenedSettingsThisLaunch = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            _ = self.openFullDiskAccessSettings()
        }
    }

    @discardableResult
    func openFullDiskAccessSettings() -> Bool {
        let workspace = NSWorkspace.shared
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]

        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if workspace.open(url) { return true }
        }

        let fallback = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        return workspace.open(fallback)
    }

    private static func detectFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedPaths = [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist")
        ]

        for url in protectedPaths where FileManager.default.fileExists(atPath: url.path) {
            return FileManager.default.isReadableFile(atPath: url.path)
        }

        return false
    }
}
