import Foundation

struct LocalSnapshot: Identifiable, Equatable, Sendable {
    var id: String { dateString }
    var dateString: String
    var label: String
}

actor SnapshotManager {
    func list() async -> [LocalSnapshot] {
        let out = await Self.run("/usr/bin/tmutil", args: ["listlocalsnapshots", "/"])
        // Lines like: com.apple.TimeMachine.2026-10-20-120000.local
        var snaps: [LocalSnapshot] = []
        for line in out.split(separator: "\n") {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            guard s.contains("TimeMachine") || s.contains("local") else { continue }
            let datePart = s
                .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                .replacingOccurrences(of: ".local", with: "")
            snaps.append(LocalSnapshot(dateString: datePart, label: s))
        }
        return snaps
    }

    /// Deletes a local snapshot by date string (yyyy-MM-dd-HHmmss). Needs admin on some systems.
    func delete(dateString: String) async -> Bool {
        let result = await PrivilegedRunner.run(
            "/usr/bin/tmutil",
            args: ["deletelocalsnapshots", dateString],
            needsAdmin: true,
            reason: "Delete local Time Machine snapshot."
        )
        return result.ok
    }

    func deleteAllListed(_ snaps: [LocalSnapshot]) async -> (ok: Int, fail: Int) {
        var ok = 0, fail = 0
        for s in snaps {
            if await delete(dateString: s.dateString) { ok += 1 } else { fail += 1 }
        }
        return (ok, fail)
    }

    private static func run(_ path: String, args: [String]) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    cont.resume(returning: "")
                }
            }
        }
    }
}
