import SwiftUI

struct StorageMapView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Storage map")
                    .font(Design.Text.section)
                    .foregroundStyle(.primary.opacity(0.75))
                Spacer()
                Button {
                    appState.refreshStorageMap()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(appState.storageScanning)
            }

            if appState.storageBuckets.isEmpty {
                Text(appState.storageScanning ? "Scanning…" : "Tap refresh to scan buckets")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.72))
            } else {
                ForEach(appState.storageBuckets) { item in
                    HStack {
                        Image(systemName: item.bucket.symbol)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.bucket.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(item.detail)
                                .font(Design.Text.micro)
                                .foregroundStyle(.primary.opacity(0.65))
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(CleanResult.formatBytes(item.bytes))
                            .font(Design.Text.micro)
                            .monospacedDigit()
                        Button("Clean") {
                            appState.cleanStorageBucket(item.bucket)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(appState.isOptimizing || item.bytes == 0)
                    }
                }
            }
        }
        .onAppear {
            if appState.storageBuckets.isEmpty {
                appState.refreshStorageMap()
            }
        }
    }
}
