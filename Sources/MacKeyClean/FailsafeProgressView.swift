import SwiftUI

/// Shows how many of the required failsafe presses have landed, so the user can
/// tell the count is being registered while the keyboard is otherwise dead.
struct FailsafeProgressView: View {
    let progress: Int
    let total: Int
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < progress ? tint : tint.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            Text("\(progress)/\(total)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint.opacity(0.85))
        }
        .animation(.easeOut(duration: 0.12), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Failsafe key pressed \(progress) of \(total) times")
    }
}
