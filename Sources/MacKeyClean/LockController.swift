import Combine
import Foundation

enum CustomUnit: String, CaseIterable, Identifiable {
    case seconds, minutes
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

@MainActor
final class LockController: ObservableObject {
    enum DurationOption: CaseIterable, Identifiable {
        case thirtySec, oneMin, threeMin, fiveMin, custom

        var id: Self { self }

        /// Seconds for each preset; `.custom` resolved via `customSeconds`.
        var presetSeconds: TimeInterval? {
            switch self {
            case .thirtySec: return 30
            case .oneMin:   return 60
            case .threeMin: return 180
            case .fiveMin:  return 300
            case .custom:   return nil
            }
        }

        var label: String {
            switch self {
            case .thirtySec: return "30 sec"
            case .oneMin:   return "1 min"
            case .threeMin: return "3 min"
            case .fiveMin:  return "5 min"
            case .custom:   return "Custom"
            }
        }
    }

    @Published var mode: LockMode = .keyboardOnly
    @Published var duration: DurationOption = .oneMin
    @Published var customSeconds: Int = 60          // value for `.custom`
    @Published var customUnit: CustomUnit = .seconds
    @Published var isLocked = false
    @Published var lockedUntil: Date? = nil
    @Published var permissionGranted = false
    @Published var tapFailed = false
    @Published var now: Date = Date()

    private var tickTimer: Timer?

    /// Effective interval in seconds, resolving `.custom` + unit.
    private var effectiveInterval: TimeInterval? {
        switch duration {
        case .custom:
            let base = TimeInterval(max(1, customSeconds))
            return customUnit == .minutes ? base * 60 : base
        default:
            return duration.presetSeconds
        }
    }

    func checkPermission() {
        permissionGranted = Permissions.hasListenAccess()
        if permissionGranted {
            let installed = KeyboardBlocker.shared.install()
            tapFailed = !installed
        }
    }

    func requestPermission() {
        Permissions.requestListenAccess()
        Permissions.openInputMonitoringSettings()
    }

    func select(mode: LockMode) {
        self.mode = mode
        // Keyboard & Trackpad must always be timed.
        if mode == .keyboardAndTrackpad && duration == .custom && effectiveInterval == nil {
            duration = .oneMin
        }
    }

    func lock() {
        KeyboardBlocker.shared.mode = mode
        KeyboardBlocker.shared.isLocked = true
        lockedUntil = effectiveInterval.map { Date().addingTimeInterval($0) }
        isLocked = true
        startTick()
    }

    func unlock() {
        isLocked = false
        KeyboardBlocker.shared.isLocked = false
        lockedUntil = nil
        tickTimer?.invalidate()
        tickTimer = nil
    }

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
        }
    }
}
