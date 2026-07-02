import Foundation
import ServiceManagement

/// Launch-at-login for the app, via the modern `SMAppService` API (macOS 13+).
/// The registration itself is the source of truth — no separate UserDefaults
/// flag to drift out of sync.
enum LoginItem {
    /// Whether the app is currently registered to open at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Turn launch-at-login on or off. Returns the resulting state (false if the
    /// change failed, e.g. the user disabled it in System Settings > Login Items).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Whitespace: launch-at-login change failed: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
