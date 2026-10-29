import SwiftUI

struct ActionReportBanner: View {
    let report: ActionReport

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(TurboTheme.bandColor(.good))
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text(report.summaryLine)
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TurboTheme.bandColor(.good).opacity(0.12))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
