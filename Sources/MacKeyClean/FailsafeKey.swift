import AppKit
import Foundation

/// Physical key the user presses repeatedly to force-end a cleaning session
/// while the event tap is swallowing every keystroke.
struct FailsafeKey: Equatable {
    var keyCode: Int64
    var label: String

    static let escape = FailsafeKey(keyCode: 53, label: "Esc")

    /// Modifier-only keys arrive as `.flagsChanged`, never as `.keyDown`,
    /// so they can never trigger the failsafe and are rejected while recording.
    static func isModifier(_ keyCode: Int64) -> Bool {
        (54...63).contains(keyCode)
    }

    private static let namedKeys: [Int64: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        71: "Clear", 76: "Enter", 117: "⌦",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        114: "Help", 81: "=", 75: "/", 67: "*", 78: "-", 69: "+",
    ]

    /// Human label for a captured key event.
    static func label(keyCode: Int64, characters: String?) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let characters, !characters.isEmpty, characters != "\u{1B}" {
            return characters.uppercased()
        }
        return "Key \(keyCode)"
    }
}
