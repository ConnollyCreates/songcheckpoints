import Foundation
import UIKit

/// Timestamped log of everything the test needs to answer: which button path fired,
/// whether the app stayed awake while locked, queue behaviour, interruptions.
/// Kept in memory for the Test Log tab and appended to a file you can share.
@MainActor
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let appState: String
        let category: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []
    let fileURL: URL
    private let clock: DateFormatter
    private let maxEntries = 4000

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("checkpoints-test-log.txt")
        clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss.SSS"
    }

    func log(_ category: String, _ message: String) {
        let entry = Entry(date: Date(), appState: Self.appStateLabel(), category: category, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        append(line(for: entry))
    }

    func timeString(_ date: Date) -> String {
        clock.string(from: date)
    }

    func line(for entry: Entry) -> String {
        "\(timeString(entry.date)) [\(entry.appState)] \(entry.category): \(entry.message)"
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
        log("LOG", "Log cleared")
    }

    /// FG = app on screen, BG = backgrounded/locked but running, IN = inactive (e.g. Control Center open).
    static func appStateLabel() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "FG"
        case .inactive: return "IN"
        case .background: return "BG"
        @unknown default: return "??"
        }
    }

    private func append(_ text: String) {
        let data = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

enum DeviceInfo {
    /// Hardware identifier, e.g. "iPhone14,5".
    static var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
