#!/usr/bin/env swift
import Foundation
import Darwin

// Lightweight smoke test of Mach metrics without launching UI.
// Run: swift Scripts/smoke_test.swift

func sampleMemory() -> Double? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    let page = UInt64(vm_kernel_page_size)
    let used = UInt64(stats.wire_count + stats.active_count + stats.compressor_page_count) * page
    let total = ProcessInfo.processInfo.physicalMemory
    return Double(used) / Double(total)
}

print("== FGMacOS Optimizer smoke ==")
guard let mem = sampleMemory() else {
    fputs("FAIL: memory sample\n", stderr)
    exit(1)
}
print(String(format: "RAM pressure ≈ %.1f%%", mem * 100))
print("Thermal: \(ProcessInfo.processInfo.thermalState.rawValue) (0=nominal)")
print("Physical memory: \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB")
print("PASS: core metrics readable")
