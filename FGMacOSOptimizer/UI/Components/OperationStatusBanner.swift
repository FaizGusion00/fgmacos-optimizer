import SwiftUI

/// Persistent “working…” strip so Clean / Turbo / Free RAM never feel frozen.
struct OperationStatusBanner: View {
    let title: String
    var detail: String? = nil

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(CleanerTheme.accent.opacity(0.25), lineWidth: 2)
                    .frame(width: 22, height: 22)
                ProgressView()
                    .controlSize(.small)
                    .tint(CleanerTheme.accent)
            }
            .scaleEffect(pulse ? 1.05 : 0.95)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("Please wait — don’t quit the app")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CleanerTheme.accent.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CleanerTheme.accent.opacity(0.28), lineWidth: 1)
                )
        )
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). Working, please wait.")
    }
}
