import WidgetKit
import SwiftUI

struct MetricsEntry: TimelineEntry {
    let date: Date
    let cpu: Double
    let ramGB: Double
    let turbo: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MetricsEntry {
        MetricsEntry(date: Date(), cpu: 0.22, ramGB: 8.0, turbo: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MetricsEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MetricsEntry>) -> Void) {
        let entry = load()
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> MetricsEntry {
        if let payload = WidgetSnapshotStore.read() {
            return MetricsEntry(
                date: payload.updatedAt,
                cpu: payload.cpu,
                ramGB: payload.ramAvailableGB,
                turbo: payload.turbo
            )
        }
        return MetricsEntry(date: Date(), cpu: 0, ramGB: 0, turbo: false)
    }
}

struct FGOptimizerWidgetEntryView: View {
    var entry: MetricsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FG Optimizer")
                    .font(.caption.weight(.bold))
                Spacer()
                if entry.turbo {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.red)
                }
            }
            Text("CPU \(Int(entry.cpu * 100))%")
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(String(format: "RAM %.1f GB free", entry.ramGB))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

@main
struct FGOptimizerWidget: Widget {
    let kind = "FGOptimizerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FGOptimizerWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("FGMacOS Optimizer")
        .description("CPU and free RAM at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

enum WidgetSnapshotStore {
    static let fileName = "metrics_snapshot.json"
    static let sharedTempURL = URL(fileURLWithPath: "/tmp/com.fgmacos.optimizer.metrics.json")

    struct Payload: Codable {
        var cpu: Double
        var ramAvailableGB: Double
        var ramUsedFraction: Double
        var turbo: Bool
        var thermal: Int
        var pressure: Int
        var updatedAt: Date
    }

    static func read() -> Payload? {
        let candidates = [
            sharedTempURL,
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FGMacOSOptimizer/\(fileName)")
        ].compactMap { $0 }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let payload = try? dec.decode(Payload.self, from: data) {
                return payload
            }
        }
        return nil
    }
}
