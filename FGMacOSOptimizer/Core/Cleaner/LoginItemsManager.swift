import Foundation
import ServiceManagement
import AppKit

struct StartupItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case loginItem, userAgent, systemAgent }
    var id: String { path + kind.rawValue }
    var name: String
    var path: String
    var kind: Kind
    var enabled: Bool
    var isApple: Bool
}

actor LoginItemsManager {
    func list() async -> [StartupItem] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var items: [StartupItem] = []
                let fm = FileManager.default

                let userAgents = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
                if let children = try? fm.contentsOfDirectory(atPath: userAgents) {
                    for name in children where name.hasSuffix(".plist") {
                        let path = (userAgents as NSString).appendingPathComponent(name)
                        let apple = name.hasPrefix("com.apple.")
                        items.append(StartupItem(
                            name: name.replacingOccurrences(of: ".plist", with: ""),
                            path: path,
                            kind: .userAgent,
                            enabled: true,
                            isApple: apple
                        ))
                    }
                }

                // Disabled user agents
                let disabled = (userAgents as NSString).appendingPathComponent("Disabled")
                if let children = try? fm.contentsOfDirectory(atPath: disabled) {
                    for name in children where name.hasSuffix(".plist") {
                        let path = (disabled as NSString).appendingPathComponent(name)
                        items.append(StartupItem(
                            name: name.replacingOccurrences(of: ".plist", with: ""),
                            path: path,
                            kind: .userAgent,
                            enabled: false,
                            isApple: name.hasPrefix("com.apple.")
                        ))
                    }
                }

                for sysRoot in ["/Library/LaunchAgents", "/Library/LaunchDaemons"] {
                    if let children = try? fm.contentsOfDirectory(atPath: sysRoot) {
                        for name in children where name.hasSuffix(".plist") {
                            let path = (sysRoot as NSString).appendingPathComponent(name)
                            items.append(StartupItem(
                                name: name.replacingOccurrences(of: ".plist", with: ""),
                                path: path,
                                kind: .systemAgent,
                                enabled: true,
                                isApple: name.hasPrefix("com.apple.")
                            ))
                        }
                    }
                }

                cont.resume(returning: items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
        }
    }

    /// Disable user LaunchAgent by unloading and moving to Disabled/.
    func setEnabled(_ item: StartupItem, enabled: Bool) async -> Bool {
        guard item.kind == .userAgent, !item.isApple else { return false }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let agents = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
                let disabledDir = (agents as NSString).appendingPathComponent("Disabled")
                try? fm.createDirectory(atPath: disabledDir, withIntermediateDirectories: true)

                if enabled {
                    // Move back from Disabled → LaunchAgents and load
                    let dest = (agents as NSString).appendingPathComponent((item.path as NSString).lastPathComponent)
                    do {
                        if item.path != dest {
                            try fm.moveItem(atPath: item.path, toPath: dest)
                        }
                        _ = Self.run("/bin/launchctl", args: ["load", dest])
                        cont.resume(returning: true)
                    } catch {
                        cont.resume(returning: false)
                    }
                } else {
                    let dest = (disabledDir as NSString).appendingPathComponent((item.path as NSString).lastPathComponent)
                    _ = Self.run("/bin/launchctl", args: ["unload", item.path])
                    do {
                        if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
                        try fm.moveItem(atPath: item.path, toPath: dest)
                        cont.resume(returning: true)
                    } catch {
                        cont.resume(returning: false)
                    }
                }
            }
        }
    }

    private static func run(_ path: String, args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
