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
                if appState.storageScanning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button {
                    appState.refreshStorageMap()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(appState.storageScanning || appState.isOptimizing)
            }

            if appState.storageBuckets.isEmpty {
                Text(appState.storageScanning ? "Scanning…" : "Tap refresh to scan buckets")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.72))
            } else {
                ForEach(appState.storageBuckets) { item in
                    storageRow(item)
                }
            }
        }
        .onAppear {
            if appState.storageBuckets.isEmpty {
                appState.refreshStorageMap()
            }
        }
    }

    private func storageRow(_ item: StorageBucketSize) -> some View {
        let cleaning = appState.cleaningBucket == item.bucket
        return HStack {
            Image(systemName: item.bucket.symbol)
                .frame(width: 16)
                .foregroundStyle(cleaning ? CleanerTheme.accent : .primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.bucket.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(cleaning ? "Cleaning… please wait" : item.detail)
                    .font(Design.Text.micro)
                    .foregroundStyle(cleaning ? CleanerTheme.accent : .primary.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(CleanResult.formatBytes(item.bytes))
                    .font(Design.Text.micro)
                    .monospacedDigit()
                if item.reclaimableBytes > 0, item.reclaimableBytes != item.bytes {
                    Text("~\(CleanResult.formatBytes(item.reclaimableBytes)) cleanable")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(CleanerTheme.accent)
                }
            }
            if cleaning {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 44)
            } else {
                Button("Clean") {
                    appState.cleanStorageBucket(item.bucket)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(appState.isOptimizing || (item.reclaimableBytes == 0 && item.bytes == 0))
            }
        }
        .padding(.vertical, 2)
        .animation(.easeInOut(duration: 0.2), value: cleaning)
    }
}
