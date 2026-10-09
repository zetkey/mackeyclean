import AppKit
import SwiftUI

/// Borderless black window that covers every screen while a session runs.
/// It never becomes key: all keyboard events must reach the event tap, otherwise
/// the failsafe key could never fire.
@MainActor
final class BlackoutController {
    private var windows: [NSWindow] = []
    private let onStop: () -> Void

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }

    var isVisible: Bool { !windows.isEmpty }

    func show(status: String, hint: String, progress: Int, total: Int) {
        guard windows.isEmpty else {
            update(status: status, hint: hint, progress: progress, total: total)
            return
        }
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = NSHostingView(
                rootView: BlackoutView(
                    status: status, hint: hint, progress: progress, total: total, onStop: onStop)
            )
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func update(status: String, hint: String, progress: Int, total: Int) {
        for window in windows {
            window.contentView = NSHostingView(
                rootView: BlackoutView(
                    status: status, hint: hint, progress: progress, total: total, onStop: onStop)
            )
        }
    }

    func hide() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }
}

private struct BlackoutView: View {
    let status: String
    let hint: String
    let progress: Int
    let total: Int
    let onStop: () -> Void

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 24) {
                Text(status)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Button(action: onStop) {
                    Text("Stop cleaning")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(.white.opacity(0.14)))
                .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                .foregroundStyle(.white)
                VStack(spacing: 10) {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    FailsafeProgressView(progress: progress, total: total, tint: .white)
                }
            }
        }
        .ignoresSafeArea()
    }
}
