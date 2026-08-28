import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var controller: LockController

    private let ringSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 16) {
            header
            if !controller.permissionGranted || controller.tapFailed {
                permissionCard
            }
            settingsCard
            Spacer(minLength: 0)
            actionArea
        }
        .padding(20)
        .frame(width: 360, height: 440)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.55),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background(WindowAccessor { window in
            window?.level = controller.isLocked ? .floating : .normal
        })
        .onAppear {
            controller.checkPermission()
            if !controller.permissionGranted {
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    Task { @MainActor in
                        if controller.permissionGranted { return }
                        controller.checkPermission()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
            Text("KeyClean")
                .font(.title2.bold())
        }
        .padding(.top, 4)
    }

    // MARK: - Permission

    private var permissionCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                Text("KeyClean needs Input Monitoring permission to block keyboard input.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 8) {
                Button {
                    controller.requestPermission()
                } label: {
                    Label("Grant Input Monitoring", systemImage: "hand.raised.fill")
                }
                .buttonStyle(.borderedProminent)
                if controller.tapFailed {
                    Button("Retry") {
                        controller.checkPermission()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(spacing: 12) {
            modeRow
            Divider()
            durationRow
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lock mode")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Lock mode", selection: Binding(
                get: { controller.mode },
                set: { controller.select(mode: $0) }
            )) {
                Text("Keyboard").tag(LockMode.keyboardOnly)
                Text("Keyboard & Trackpad").tag(LockMode.keyboardAndTrackpad)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var durationRow: some View {
        VStack {
            Picker("Auto-unlock after", selection: $controller.duration) {
                ForEach(LockController.DurationOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            if controller.duration == .custom {
                customInput
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var customInput: some View {
        HStack(spacing: 8) {
            TextField("Value", value: $controller.customSeconds, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .onChange(of: controller.customSeconds) { new in
                    controller.customSeconds = max(1, new)
                }
            Picker("Unit", selection: $controller.customUnit) {
                ForEach(CustomUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionArea: some View {
        if controller.isLocked {
            lockedView
        } else {
            Button {
                controller.lock()
            } label: {
                Label("Lock", systemImage: "lock.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
            .disabled(!controller.permissionGranted)
        }
    }

    private var lockedView: some View {
        VStack(spacing: 14) {
            countdownRing

            if controller.mode == .keyboardOnly {
                Button {
                    controller.unlock()
                } label: {
                    Label("Unlock", systemImage: "lock.open.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            } else {
                Text("Unlocks automatically in \(remainingText(until: controller.lockedUntil ?? controller.now))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Countdown ring

    private var countdownRing: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.red.opacity(0.15), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(.red, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let lockedUntil = controller.lockedUntil {
                    Text(remainingText(until: lockedUntil))
                        .font(.system(.title, design: .monospaced))
                        .monospacedDigit()
                        .bold()
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityLabel("Locked")

            Text("Locked")
                .font(.headline)
                .foregroundStyle(.red)
        }
    }

    private var ringProgress: CGFloat {
        guard let lockedUntil = controller.lockedUntil else { return 0 }
        let base = TimeInterval(controller.customSeconds)
        let total = controller.duration.presetSeconds
            ?? (controller.customUnit == .minutes ? base * 60 : base)
        guard total > 0 else { return 0 }
        let remaining = max(0, lockedUntil.timeIntervalSince(controller.now))
        return CGFloat(min(1, max(0, remaining / total)))
    }

    private func remainingText(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(controller.now).rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - WindowAccessor

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            onWindow(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            onWindow(nsView?.window)
        }
    }
}
