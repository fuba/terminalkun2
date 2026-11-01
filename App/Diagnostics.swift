import Foundation
import MetricKit
import TerminalRenderer

final class Diagnostics: NSObject, MXMetricManagerSubscriber {
    private let directory: URL
    private var performanceTimer: Timer?
    init(directory: URL) {
        self.directory = directory
        super.init()
        MXMetricManager.shared.add(self)
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.recordPerformance() }
    }
    deinit { performanceTimer?.invalidate(); MXMetricManager.shared.remove(self) }
    private func recordPerformance() {
        let slow = TerminalProfiling.summaries().filter { $0.maxMs > 16 }
        defer { TerminalProfiling.reset() }
        guard !slow.isEmpty else { return }
        let url = directory.appendingPathComponent("perf.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            if size > 2 * 1024 * 1024 { try? handle.truncate(atOffset: 0); try? handle.seek(toOffset: 0) }
            try? handle.write(contentsOf: Data((Date().formatted(.iso8601) + "\n" + TerminalProfiling.report(summaries: slow) + "\n").utf8))
        }
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads { write(payload.jsonRepresentation(), kind: "crash") }
    }
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { write(payload.jsonRepresentation(), kind: "metrics") }
    }
    private func write(_ data: Data, kind: String) {
        guard data.count <= 8 * 1024 * 1024 else { return }
        let url = directory.appendingPathComponent("\(kind)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json")
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(kind + "-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(20) { try? FileManager.default.removeItem(at: old) }
    }
}
