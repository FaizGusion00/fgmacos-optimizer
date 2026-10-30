import Foundation

actor DevCleanupPack {
    func scan() async -> [CleanItem] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var items: [CleanItem] = []
                let home = NSHomeDirectory()
                let lib = (home as NSString).appendingPathComponent("Library")

                let targets: [(id: String, title: String, path: String, risk: CleanRisk)] = [
                    // Review (not pre-ticked): wiping DerivedData forces full rebuilds tomorrow morning.
                    ("dev.derived", "Xcode DerivedData", (lib as NSString).appendingPathComponent("Developer/Xcode/DerivedData"), .review),
                    ("dev.archives", "Xcode Archives", (lib as NSString).appendingPathComponent("Developer/Xcode/Archives"), .review),
                    ("dev.sim", "CoreSimulator caches", (lib as NSString).appendingPathComponent("Developer/CoreSimulator/Caches"), .safeJunk),
                    ("dev.pods", "CocoaPods cache", (lib as NSString).appendingPathComponent("Caches/CocoaPods"), .safeJunk),
                    ("dev.npm", "npm cache", (home as NSString).appendingPathComponent(".npm/_cacache"), .safeJunk),
                    ("dev.pip", "pip cache", (lib as NSString).appendingPathComponent("Caches/pip"), .safeJunk)
                ]

                for t in targets {
                    guard FileManager.default.fileExists(atPath: t.path) else { continue }
                    guard CleanSafety.assertSafeToRemove(path: t.path) else { continue }
                    let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: t.path))
                    guard size > 0 else { continue }
                    items.append(CleanItem(
                        id: t.id,
                        category: .dev,
                        title: t.title,
                        subtitle: t.path,
                        bytes: size,
                        paths: [t.path],
                        risk: t.risk,
                        disposal: .delete,
                        selected: t.risk == .safeJunk
                    ))
                }

                // Homebrew dry-run size estimate (best-effort).
                if let brew = Self.resolveBrew() {
                    let out = Self.run(brew, args: ["cleanup", "-n"])
                    if !out.isEmpty {
                        items.append(CleanItem(
                            id: "dev.brew",
                            category: .dev,
                            title: "Homebrew cleanup",
                            subtitle: "brew cleanup (confirm runs for real)",
                            bytes: Self.parseBrewBytes(out),
                            paths: [],
                            risk: .review,
                            disposal: .delete,
                            selected: false,
                            meta: ["action": "brew-cleanup", "brew": brew]
                        ))
                    }
                }

                // Unavailable simulators
                items.append(CleanItem(
                    id: "dev.sim.unavailable",
                    category: .dev,
                    title: "Unavailable simulators",
                    subtitle: "xcrun simctl delete unavailable",
                    bytes: 0,
                    paths: [],
                    risk: .review,
                    disposal: .delete,
                    selected: false,
                    meta: ["action": "simctl-unavailable"]
                ))

                cont.resume(returning: items)
            }
        }
    }

    func runSpecial(_ item: CleanItem) async -> CleanRunResult {
        var result = CleanRunResult()
        switch item.meta["action"] {
        case "brew-cleanup":
            let brew = item.meta["brew"] ?? Self.resolveBrew() ?? ""
            guard !brew.isEmpty else {
                result.errors.append("brew not found")
                return result
            }
            _ = Self.run(brew, args: ["cleanup"])
            result.itemsProcessed = 1
            result.freedBytes = item.bytes
        case "simctl-unavailable":
            _ = Self.run("/usr/bin/xcrun", args: ["simctl", "delete", "unavailable"])
            result.itemsProcessed = 1
        default:
            break
        }
        return result
    }

    private static func resolveBrew() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ path: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func parseBrewBytes(_ text: String) -> UInt64 {
        // Look for patterns like "123.4MB" or "1.2GB"
        var total: UInt64 = 0
        let pattern = try? NSRegularExpression(pattern: #"([\d.]+)\s*(GB|MB|KB)"#, options: .caseInsensitive)
        let range = NSRange(text.startIndex..., in: text)
        pattern?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 3,
                  let nRange = Range(match.range(at: 1), in: text),
                  let uRange = Range(match.range(at: 2), in: text),
                  let n = Double(text[nRange]) else { return }
            let unit = text[uRange].uppercased()
            if unit == "GB" { total += UInt64(n * 1_073_741_824) }
            else if unit == "MB" { total += UInt64(n * 1_048_576) }
            else { total += UInt64(n * 1024) }
        }
        return total
    }
}
