import CoreGraphics
import AppKit

enum Permissions {
    static func hasListenAccess() -> Bool { CGPreflightListenEventAccess() }
    static func requestListenAccess() { _ = CGRequestListenEventAccess() }
    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
