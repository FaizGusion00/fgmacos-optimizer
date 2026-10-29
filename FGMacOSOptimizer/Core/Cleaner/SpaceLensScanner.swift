import Foundation

struct SpaceNode: Identifiable, Equatable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var bytes: UInt64
    var children: [SpaceNode]
}

actor SpaceLensScanner {
    func scanHome(maxDepth: Int = 2) async -> [SpaceNode] {
        let home = NSHomeDirectory()
        let apps = "/Applications"
        async let homeNodes = measureChildren(of: home, depth: 0, maxDepth: maxDepth)
        async let appNodes = measureChildren(of: apps, depth: 0, maxDepth: 1)
        let (h, a) = await (homeNodes, appNodes)
        return [
            SpaceNode(name: "Home", path: home, bytes: h.reduce(0) { $0 + $1.bytes }, children: h),
            SpaceNode(name: "Applications", path: apps, bytes: a.reduce(0) { $0 + $1.bytes }, children: a)
        ]
    }

    private func measureChildren(of path: String, depth: Int, maxDepth: Int) async -> [SpaceNode] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                guard let names = try? fm.contentsOfDirectory(atPath: path) else {
                    cont.resume(returning: [])
                    return
                }
                var nodes: [SpaceNode] = []
                for name in names where !name.hasPrefix(".") {
                    let child = (path as NSString).appendingPathComponent(name)
                    // Skip heavy protected roots at home level
                    if depth == 0 && (name == "Library" || name == "Photos Library.photoslibrary") {
                        let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: child))
                        nodes.append(SpaceNode(name: name, path: child, bytes: size, children: []))
                        continue
                    }
                    let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: child))
                    var kids: [SpaceNode] = []
                    if depth + 1 < maxDepth {
                        // sync shallow for nested — keep cheap
                        if let sub = try? fm.contentsOfDirectory(atPath: child) {
                            for s in sub.prefix(40) where !s.hasPrefix(".") {
                                let p = (child as NSString).appendingPathComponent(s)
                                let sz = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: p))
                                if sz > 0 {
                                    kids.append(SpaceNode(name: s, path: p, bytes: sz, children: []))
                                }
                            }
                            kids.sort { $0.bytes > $1.bytes }
                        }
                    }
                    if size > 0 {
                        nodes.append(SpaceNode(name: name, path: child, bytes: size, children: kids))
                    }
                }
                cont.resume(returning: nodes.sorted { $0.bytes > $1.bytes })
            }
        }
    }
}
