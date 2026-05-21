import Foundation

actor AIMetricsLogger {
    static let shared = AIMetricsLogger()

    private var durations: [String: [TimeInterval]] = [:]

    func record(task: AITask, duration: TimeInterval, engine: String, success: Bool) {
        var bucket = durations[task.telemetryName] ?? []
        bucket.append(duration)
        if bucket.count > 200 {
            bucket.removeFirst(bucket.count - 200)
        }
        durations[task.telemetryName] = bucket

        let status = success ? "ok" : "error"
        print("[AIMetrics] task=\(task.telemetryName) status=\(status) duration=\(String(format: "%.3f", duration))s engine=\(engine)")
    }

    func snapshot() -> [String: (p50: TimeInterval, p95: TimeInterval)] {
        var result: [String: (p50: TimeInterval, p95: TimeInterval)] = [:]
        for (task, values) in durations {
            guard !values.isEmpty else { continue }
            let sorted = values.sorted()
            let p50Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.50))
            let p95Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
            result[task] = (sorted[p50Index], sorted[p95Index])
        }
        return result
    }
}
