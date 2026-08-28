import CoreGraphics
import Foundation

enum LockMode {
    case keyboardOnly          // swallow keyboard + media, leave mouse alive
    case keyboardAndTrackpad   // swallow keyboard + media + mouse
}

// NX_SYSDEFINED (14) — catches volume/brightness/play-pause; not a named Swift CGEventType member.
private let kCGEventSystemDefined = CGEventType(rawValue: 14)!

// CGEventMaskBit is a C macro, unavailable in Swift — replicate it.
private func eventBit(_ t: CGEventType) -> CGEventMask { 1 << t.rawValue }

// Must be a free function (not a static method) to form a C function pointer.
private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = blocker.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return nil
    }
    guard blocker.isLocked else { return Unmanaged.passUnretained(event) }

    switch type {
    case .keyDown, .keyUp, .flagsChanged, kCGEventSystemDefined:
        return nil
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
         .mouseMoved, .leftMouseDragged, .rightMouseDragged,
         .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel:
        return blocker.mode == .keyboardAndTrackpad ? nil : Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}

final class KeyboardBlocker {
    // Read by the C callback on the main run loop; written only from the main thread.
    var isLocked = false
    var mode: LockMode = .keyboardOnly

    static let shared = KeyboardBlocker()

    var eventTap: CFMachPort?          // internal access for the free tapCallback
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?

    private init() {}

    private static let keyboardMask: CGEventMask =
        eventBit(.keyDown) | eventBit(.keyUp) |
        eventBit(.flagsChanged) | eventBit(kCGEventSystemDefined)

    private static let mouseMask: CGEventMask =
        eventBit(.leftMouseDown) | eventBit(.leftMouseUp) |
        eventBit(.rightMouseDown) | eventBit(.rightMouseUp) |
        eventBit(.mouseMoved) | eventBit(.leftMouseDragged) |
        eventBit(.rightMouseDragged) | eventBit(.otherMouseDown) |
        eventBit(.otherMouseUp) | eventBit(.otherMouseDragged) |
        eventBit(.scrollWheel)

    func install() -> Bool {
        guard eventTap == nil else { return true }
        let mask = Self.keyboardMask | Self.mouseMask
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        startHealthCheck()
        return true
    }

    private func startHealthCheck() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                if !CGEvent.tapIsEnabled(tap: tap) { self.reinstall() }
            }
        }
    }

    private func reinstall() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        _ = install()
    }
}
