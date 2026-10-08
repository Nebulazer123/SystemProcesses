import Foundation
import Darwin

// Read-only app profiler. No process commands, credentials, or signals.
let pid = pid_t(CommandLine.arguments[1])!
let duration = Double(CommandLine.arguments[2])!
let path = CommandLine.arguments[3]
FileManager.default.createFile(atPath: path, contents: nil)
let output = FileHandle(forWritingAtPath: path)!
let started = Date()
var clock = mach_timebase_info_data_t(); mach_timebase_info(&clock)
var expectedStart: UInt64?
var expectedUUID: String?
repeat {
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard result == 0 else { break }
    let uuid = withUnsafeBytes(of: usage.ri_uuid) { bytes in
        bytes.map { String(format: "%02x", $0) }.joined()
    }
    if expectedStart == nil { expectedStart = usage.ri_proc_start_abstime; expectedUUID = uuid }
    guard expectedStart == usage.ri_proc_start_abstime, expectedUUID == uuid else {
        print("Target identity changed; sampling stopped."); break
    }
    var sample: [String: Any] = ["time": Date().timeIntervalSince1970, "pid": pid,
        "process_start_abstime": usage.ri_proc_start_abstime, "process_uuid": uuid,
        "rss_bytes": usage.ri_resident_size, "footprint_bytes": usage.ri_phys_footprint,
        "cpu_seconds": Double(usage.ri_user_time+usage.ri_system_time)*Double(clock.numer)/Double(clock.denom)/1e9,
        "package_idle_wakeups": usage.ri_pkg_idle_wkups, "interrupt_wakeups": usage.ri_interrupt_wkups]
    // New kernels expose an estimated process energy counter; retain its provenance.
    // Missing/zero counters do not establish zero energy use.
    var extended = rusage_info_v6()
    let extendedResult = withUnsafeMutablePointer(to: &extended) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
    }
    if extendedResult == 0 {
        sample["kernel_energy_nj"] = extended.ri_energy_nj
        sample["kernel_performance_energy_nj"] = extended.ri_penergy_nj
    }
    if CommandLine.arguments.count > 4,
       let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[4])),
       let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let time = state["time"] as? Double, Date().timeIntervalSince1970-time < 10 {
        sample["menu_shown"] = state["shown"]; sample["retained_history"] = state["retainedHistory"]
    }
    output.write(try! JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys])); output.write(Data([10]))
    fflush(stdout)
    Thread.sleep(forTimeInterval: 5)
} while Date().timeIntervalSince(started) < duration
try? output.close()
print("Profile complete: \(path)")
