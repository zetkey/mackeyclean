import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: LockController

    /// Local key monitor used only while capturing a new failsafe key.
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 16) {
            header
            if !controller.permissionGranted || controller.tapFailed {
                permissionBanner
            }
            if controller.isLocked {
                sessionPanel
            } else {
                settingsPanel
            }
            Spacer(minLength: 0)
            primaryAction
        }
        .padding(22)
        .frame(width: 400, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            WindowAccessor { window in
                window?.level = controller.isLocked ? .floating : .normal
            }
        )
        .onAppear { controller.checkPermission() }
        .onChange(of: controller.isRecordingKey) { recording in
            recording ? installKeyMonitor() : removeKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.tint.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "keyboard")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.tint)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("KeyClean")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(controller.isLocked ? "Session running" : "Clean your keyboard safely")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Permission

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Input Monitoring permission is required to block keystrokes.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button("Open Settings") { controller.requestPermission() }
                    .controlSize(.small)
                if controller.tapFailed {
                    Button("Retry") { controller.checkPermission() }
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.orange.opacity(0.12)))
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            pickerBlock("Lock mode") {
                Picker("", selection: $controller.mode) {
                    Text("Keyboard").tag(LockMode.keyboardOnly)
                    Text("Keyboard + Trackpad").tag(LockMode.keyboardAndTrackpad)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            divider
            pickerBlock("Auto-unlock") {
                Picker("", selection: $controller.duration) {
                    ForEach(LockController.DurationOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if controller.duration == .custom {
                    HStack(spacing: 8) {
                        TextField("", value: $controller.customSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                        Picker("", selection: $controller.customUnit) {
                            ForEach(CustomUnit.allCases) { unit in
                                Text(unit.label).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                }
            }
            divider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    caption("Blank screen")
                    Spacer(minLength: 0)
                    Toggle("", isOn: $controller.blankScreen)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                note(
                    "Hides everything behind a black screen while cleaning. The overlay still shows a Stop button."
                )
            }
            .padding(.vertical, 12)
            divider
            VStack(alignment: .leading, spacing: 8) {
                caption("Failsafe key")
                HStack(spacing: 8) {
                    Text(controller.isRecordingKey ? "Press a key…" : controller.failsafeKey.label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(controller.isRecordingKey ? .orange : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                    Button(controller.isRecordingKey ? "Cancel" : "Change") {
                        controller.isRecordingKey
                            ? controller.cancelKeyRecording() : controller.beginKeyRecording()
                    }
                    .controlSize(.small)
                    Spacer(minLength: 0)
                }
                note(
                    "Press \(controller.failsafeKey.label) \(LockController.failsafePresses)× in a row to force-stop a session."
                )
            }
            .padding(.vertical, 12)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.4)))
    }

    private func pickerBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            caption(title)
            content()
        }
        .padding(.vertical, 12)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(.quaternary).frame(height: 1)
    }

    // MARK: - Active session

    private var sessionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(controller.statusText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
            if controller.lockedUntil != nil {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(.tint)
                            .frame(width: geometry.size.width * controller.ringProgress)
                    }
                }
                .frame(height: 6)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(controller.failsafeHint, systemImage: "escape")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                FailsafeProgressView(
                    progress: controller.failsafePressesSoFar,
                    total: LockController.failsafePresses
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.4)))
    }

    // MARK: - Primary action

    @ViewBuilder
    private var primaryAction: some View {
        if controller.isLocked {
            Button {
                controller.unlock()
            } label: {
                Text("Stop cleaning")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
        } else {
            Button {
                controller.lock()
            } label: {
                Text("Start cleaning")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.permissionGranted)
        }
    }

    // MARK: - Failsafe key capture

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                controller.cancelKeyRecording()
            } else {
                controller.handleRecordedKey(
                    keyCode: Int64(event.keyCode),
                    characters: event.charactersIgnoringModifiers
                )
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - WindowAccessor

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onWindow(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in onWindow(nsView?.window) }
    }
}
