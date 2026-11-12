import SwiftUI

struct LogView: View {
    @EnvironmentObject private var log: DiagnosticsLog
    @AppStorage(SettingsKey.heartbeatsVisible) private var showHeartbeats = false
    @State private var markerCount = 0
    @State private var confirmClear = false

    private var visible: [DiagnosticsLog.Entry] {
        let entries = showHeartbeats ? log.entries : log.entries.filter { $0.category != "HEART" || $0.message.hasPrefix("⚠️") }
        return Array(entries.reversed())
    }

    var body: some View {
        NavigationStack {
            List(visible) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(log.timeString(entry.date))  [\(entry.appState)]  \(entry.category)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(color(for: entry))
                    Text(entry.message)
                        .font(.footnote.monospaced())
                }
            }
            .listStyle(.plain)
            .navigationTitle("Test Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        markerCount += 1
                        log.log("MARK", "──── Marker \(markerCount) ────")
                    } label: {
                        Label("Add marker", systemImage: "flag")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Show heartbeats", isOn: $showHeartbeats)
                        Button("Clear log", role: .destructive) { confirmClear = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    ShareLink(item: log.fileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .confirmationDialog("Clear the whole test log?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { log.clear() }
            }
        }
    }

    private func color(for entry: DiagnosticsLog.Entry) -> Color {
        switch entry.category {
        case "REMOTE": return .green
        case "DETECT": return .orange
        case "JUMP": return .blue
        case "MARK": return .purple
        case "HEART": return entry.message.hasPrefix("⚠️") ? .red : .secondary
        default: return .secondary
        }
    }
}
