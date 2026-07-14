import Foundation
import os

/// Lightweight wall-clock profiling for the perf-investigation pass. Active ONLY
/// under the `--profile` launch flag; a normal launch pays a single Bool check and
/// nothing else. Diagnostic scaffolding, not production telemetry — meant to point
/// the speed-up pass at the real hot paths, then be removed or kept behind the flag.
public enum PerfLog {

    /// Cached once at first use from the process arguments.
    public static let enabled: Bool = LaunchReset.isProfiling(in: CommandLine.arguments)

    private static let log = OSLog(subsystem: "com.jschwefel.medit", category: "perf")

    /// Time `body`, logging `label` + duration (ms) and `detail` when profiling is on.
    /// Returns whatever `body` returns, so it wraps an expression in place.
    @discardableResult
    public static func measure<T>(_ label: String, _ detail: @autoclosure () -> String = "",
                                  _ body: () -> T) -> T {
        guard enabled else { return body() }
        let start = DispatchTime.now().uptimeNanoseconds
        let result = body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let d = detail()
        os_log("%{public}@ %.2f ms %{public}@", log: log, type: .info, label, ms, d)
        FileHandle.standardError.write(Data("[perf] \(label) \(String(format: "%.2f", ms)) ms \(d)\n".utf8))
        return result
    }
}
