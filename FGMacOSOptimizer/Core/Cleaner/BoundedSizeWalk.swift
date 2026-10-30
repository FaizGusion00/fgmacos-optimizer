import Foundation

/// Directory size walk with BOTH a file cap and a wall-clock budget.
/// Old Macs (and one pathological folder) must never stall a scan for minutes:
/// a single `enumerator.nextObject()` can block on a huge or slow directory.
enum BoundedSizeWalk {
    struct Result: Sendable {
        var bytes: UInt64
        var files: Int
        /// True when the walk stopped early (cap or budget) — callers say "≥" / "partial".
        var partial: Bool
    }

    static func size(
        atPath path: String,
        maxFiles: Int,
        budget: TimeInterval,
        skipPackages: Bool = true
    ) -> Result {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return Result(bytes: 0, files: 0, partial: false)
        }
        if !isDir.boolValue {
            let size = (try? fm.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
            return Result(bytes: size, files: 1, partial: false)
        }
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if skipPackages { options.insert(.skipsPackageDescendants) }
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: options
        ) else {
            return Result(bytes: 0, files: 0, partial: false)
        }

        let deadline = Date().addingTimeInterval(budget)
        var total: UInt64 = 0
        var n = 0
        var partial = false
        while let item = enumerator.nextObject() as? URL {
            n += 1
            if n > maxFiles { partial = true; break }
            if Date() >= deadline { partial = true; break }
            guard let vals = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true,
                  let size = vals.fileSize else { continue }
            total += UInt64(size)
        }
        return Result(bytes: total, files: n, partial: partial)
    }

    /// Same walk, but the caller is released at `budget` even if a single filesystem call
    /// is blocked (seen: a stalled ~/Downloads froze two scan threads for minutes).
    /// The orphaned walk finishes on its own utility thread; the partial result is reported.
    static func sizeWithTimeout(
        atPath path: String,
        maxFiles: Int,
        budget: TimeInterval,
        skipPackages: Bool = true
    ) async -> Result {
        await withCheckedContinuation { (cont: CheckedContinuation<Result, Never>) in
            let gate = OneShot(cont)
            DispatchQueue.global(qos: .utility).async {
                let r = size(atPath: path, maxFiles: maxFiles, budget: budget, skipPackages: skipPackages)
                gate.resume(r)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + budget + 0.5) {
                gate.resume(Result(bytes: 0, files: 0, partial: true))
            }
        }
    }

    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<Result, Never>?
        init(_ cont: CheckedContinuation<Result, Never>) { self.cont = cont }
        func resume(_ value: Result) {
            lock.lock()
            let c = cont
            cont = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }
}
