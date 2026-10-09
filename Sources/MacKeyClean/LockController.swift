import AppKit
import Combine
import Foundation

enum CustomUnit: String, CaseIterable, Identifiable {
    case seconds, minutes
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

@MainActor
final class LockController: ObservableObject {
    enum DurationOption: String, CaseIterable, Identifiable {
        case thirtySec, oneMin, threeMin, fiveMin, custom

        var id: Self { self }

        /// Seconds for each preset; `.custom` resolved via `customSeconds`.
        var presetSeconds: TimeInterval? {
            switch self {
            case .thirtySec: return 30
            case .oneMin: return 60
            case .threeMin: return 180
            case .fiveMin: return 300
            case .custom: return nil
            }
        }

        var label: String {
            switch self {
            case .thirtySec: return "30 sec"
            case .oneMin: return "1 min"
            case .threeMin: return "3 min"
            case .fiveMin: return "5 min"
            case .custom: return "Custom"
            }
        }
    }

    static let failsafePresses = KeyboardBlocker.failsafePressesRequired

    @Published var mode: LockMode = .keyboardOnly {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }
    @Published var duration: DurationOption = .oneMin {
        didSet { defaults.set(duration.rawValue, forKey: Key.duration) }
    }
    @Published var customSeconds: Int = 60 {
        didSet {
            let clamped = min(600, max(1, customSeconds))
            guard clamped == customSeconds else {
                customSeconds = clamped
                return
            }
            defaults.set(customSeconds, forKey: Key.customSeconds)
        }
    }
    @Published var customUnit: CustomUnit = .seconds {
        didSet { defaults.set(customUnit.rawValue, forKey: Key.customUnit) }
    }
    @Published var blankScreen = false {
        didSet { defaults.set(blankScreen, forKey: Key.blankScreen) }
    }
    @Published var failsafeKey: FailsafeKey = .escape {
        didSet {
            KeyboardBlocker.shared.failsafeKeyCode = failsafeKey.keyCode
            defaults.set(failsafeKey.keyCode, forKey: Key.failsafeKeyCode)
            defaults.set(failsafeKey.label, forKey: Key.failsafeKeyLabel)
        }
    }
    @Published var isRecordingKey = false
    @Published var failsafePressesSoFar = 0
    @Published var isLocked = false
    @Published var lockedUntil: Date? = nil
    @Published var permissionGranted = false
    @Published var tapFailed = false
    @Published var now: Date = Date()

    private let defaults = UserDefaults.standard
    private var tickTimer: Timer?
    private var permissionTimer: Timer?
    /// When the last failsafe press landed, so a stale count can decay to zero.
    private var lastFailsafePressAt: Date?
    private lazy var blackout = BlackoutController { [weak self] in self?.unlock() }

    private enum Key {
        static let mode = "lockMode"
        static let duration = "duration"
        static let customSeconds = "customSeconds"
        static let customUnit = "customUnit"
        static let blankScreen = "blankScreen"
        static let failsafeKeyCode = "failsafeKeyCode"
        static let failsafeKeyLabel = "failsafeKeyLabel"
    }

    init() {
        loadSettings()
        KeyboardBlocker.shared.onFailsafe = { [weak self] in
            Task { @MainActor in self?.unlock() }
        }
        KeyboardBlocker.shared.onFailsafeProgress = { [weak self] count in
            Task { @MainActor in self?.noteFailsafeProgress(count) }
        }
    }

    /// Mirrors the tap's press counter into published state and refreshes the overlay
    /// immediately, instead of waiting for the next one-second tick.
    private func noteFailsafeProgress(_ count: Int) {
        failsafePressesSoFar = count
        lastFailsafePressAt = count > 0 ? Date() : nil
        guard isLocked, blankScreen else { return }
        blackout.update(
            status: statusText,
            hint: failsafeHint,
            progress: count,
            total: Self.failsafePresses
        )
    }

    // MARK: - Derived state

    /// Effective interval in seconds, resolving `.custom` + unit.
    var effectiveInterval: TimeInterval? {
        switch duration {
        case .custom:
            let base = TimeInterval(max(1, customSeconds))
            return customUnit == .minutes ? base * 60 : base
        default:
            return duration.presetSeconds
        }
    }

    /// Text shown on the blackout overlay and in the locked panel.
    var statusText: String {
        let remaining = lockedUntil.map { max(0, Int($0.timeIntervalSince(now).rounded())) }
        let clock = remaining.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
        switch mode {
        case .keyboardAndTrackpad:
            return clock.map { "Keyboard & trackpad locked · \($0)" } ?? "Keyboard & trackpad locked"
        case .keyboardOnly:
            return clock.map { "Cleaning keyboard · unlocks in \($0)" } ?? "Cleaning keyboard"
        }
    }

    var failsafeHint: String {
        "Press \(failsafeKey.label) \(Self.failsafePresses)× to force stop"
    }

    /// Fraction of the countdown still remaining, for the progress ring.
    var ringProgress: CGFloat {
        guard let lockedUntil, let total = effectiveInterval, total > 0 else { return 0 }
        let remaining = max(0, lockedUntil.timeIntervalSince(now))
        return CGFloat(min(1, max(0, remaining / total)))
    }

    var remainingText: String {
        guard let lockedUntil else { return "" }
        let seconds = max(0, Int(lockedUntil.timeIntervalSince(now).rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Permission

    func checkPermission() {
        permissionGranted = Permissions.hasListenAccess()
        if permissionGranted {
            tapFailed = !KeyboardBlocker.shared.install()
            stopPermissionPolling()
        }
    }

    func requestPermission() {
        Permissions.requestListenAccess()
        Permissions.openInputMonitoringSettings()
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - Session

    func lock() {
        KeyboardBlocker.shared.mode = mode
        KeyboardBlocker.shared.failsafeKeyCode = failsafeKey.keyCode
        KeyboardBlocker.shared.resetFailsafe()
        lockedUntil = effectiveInterval.map { Date().addingTimeInterval($0) }
        isLocked = true
        KeyboardBlocker.shared.isLocked = true
        if blankScreen {
            blackout.show(
                status: statusText,
                hint: failsafeHint,
                progress: 0,
                total: Self.failsafePresses
            )
        }
        startTick()
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        KeyboardBlocker.shared.isLocked = false
        KeyboardBlocker.shared.resetFailsafe()
        lockedUntil = nil
        tickTimer?.invalidate()
        tickTimer = nil
        blackout.hide()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Failsafe key capture

    func beginKeyRecording() {
        isRecordingKey = true
    }

    func cancelKeyRecording() {
        isRecordingKey = false
    }

    func handleRecordedKey(keyCode: Int64, characters: String?) {
        guard isRecordingKey, !FailsafeKey.isModifier(keyCode) else { return }
        isRecordingKey = false
        failsafeKey = FailsafeKey(
            keyCode: keyCode,
            label: FailsafeKey.label(keyCode: keyCode, characters: characters)
        )
    }

    // MARK: - Timer

    private func startTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        now = Date()
        if let lockedUntil, now >= lockedUntil {
            unlock()
            return
        }
        // A count left over from a burst that already lapsed must not linger.
        if failsafePressesSoFar > 0,
            let lastFailsafePressAt,
            now.timeIntervalSince(lastFailsafePressAt) > KeyboardBlocker.failsafeWindow
        {
            failsafePressesSoFar = 0
            self.lastFailsafePressAt = nil
        }
        if blankScreen && isLocked {
            blackout.update(
                status: statusText,
                hint: failsafeHint,
                progress: failsafePressesSoFar,
                total: Self.failsafePresses
            )
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        if let raw = defaults.string(forKey: Key.mode), let stored = LockMode(rawValue: raw) {
            mode = stored
        }
        if let raw = defaults.string(forKey: Key.duration), let stored = DurationOption(rawValue: raw) {
            duration = stored
        }
        let storedSeconds = defaults.integer(forKey: Key.customSeconds)
        if storedSeconds > 0 { customSeconds = storedSeconds }
        if let raw = defaults.string(forKey: Key.customUnit), let stored = CustomUnit(rawValue: raw) {
            customUnit = stored
        }
        if defaults.object(forKey: Key.blankScreen) != nil {
            blankScreen = defaults.bool(forKey: Key.blankScreen)
        }
        if let raw = defaults.string(forKey: Key.failsafeKeyLabel) {
            let code = defaults.object(forKey: Key.failsafeKeyCode) as? Int64 ?? FailsafeKey.escape.keyCode
            failsafeKey = FailsafeKey(keyCode: code, label: raw)
        }
    }
}
