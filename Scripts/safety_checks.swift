#!/usr/bin/env swift
import Foundation

// Mirrors WhitelistStore / Cleaner allow-list rules for regression checks.

let protectedBundles: Set<String> = [
    "com.apple.finder",
    "com.apple.Terminal",
    "com.apple.dt.Xcode",
    "com.todesktop.230313mzl4w4u92",
    "com.docker.docker",
    "com.fgmacos.optimizer"
]
let protectedNames: Set<String> = [
    "Cursor", "Terminal", "Xcode", "Docker", "Finder", "WindowServer", "kernel_task"
]

func isProtected(bundleID: String?, name: String) -> Bool {
    if let bundleID, protectedBundles.contains(bundleID) { return true }
    if protectedNames.contains(name) { return true }
    if name.contains("FGMacOS") { return true }
    return false
}

let allowedExact: Set<String> = ["Homebrew", "pip", "com.google.Chrome"]
let allowedPrefixes = ["com.apple.Safari", "com.google.Chrome", "Homebrew"]
let blocked = ["CloudKit", "Keychain", "Cookies", "Passwords"]

func isAllowedCache(_ name: String) -> Bool {
    for b in blocked where name.localizedCaseInsensitiveContains(b) { return false }
    if allowedExact.contains(name) { return true }
    for p in allowedPrefixes where name.hasPrefix(p) { return true }
    return false
}

var failed = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond { print("PASS \(msg)") }
    else { print("FAIL \(msg)"); failed += 1 }
}

expect(isProtected(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"), "Cursor whitelisted")
expect(isProtected(bundleID: nil, name: "Terminal"), "Terminal whitelisted")
expect(isProtected(bundleID: "com.fgmacos.optimizer", name: "FGMacOS Optimizer"), "self protected")
expect(!isProtected(bundleID: "com.random.app", name: "Chrome Helper"), "random app not protected")

expect(isAllowedCache("com.google.Chrome"), "Chrome cache allowed")
expect(isAllowedCache("Homebrew"), "Homebrew allowed")
expect(!isAllowedCache("CloudKit"), "CloudKit blocked")
expect(!isAllowedCache("com.apple.KeychainSomething"), "Keychain blocked")
expect(!isAllowedCache("totally.unknown.cache"), "unknown cache blocked")
expect(!isAllowedCache("pip-Cookies-mirror"), "Cookies substring blocked")

// PID kill safety
func canKill(pid: Int32) -> Bool { pid > 1 && pid != ProcessInfo.processInfo.processIdentifier }
expect(!canKill(pid: 0), "pid 0 blocked")
expect(!canKill(pid: 1), "pid 1 blocked")
expect(!canKill(pid: ProcessInfo.processInfo.processIdentifier), "self pid blocked")
expect(canKill(pid: 99999), "normal pid allowed by pid rule")

if failed > 0 {
    fputs("\n\(failed) safety check(s) failed\n", stderr)
    exit(1)
}
print("\nAll safety checks passed")
