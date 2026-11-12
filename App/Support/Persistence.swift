import Foundation
import SwiftData
import MediaPlayer

// Models follow CloudKit's rules (every property has a default, relationships are optional,
// no unique constraints) so iCloud sync can be switched on later without a migration.

@Model
final class TrackRecord {
    /// Stable identity for the recording: "store:<Apple Music ID>" when available, else "pid:<library ID>".
    var key: String = ""
    /// Device library persistent ID, used to find the song again on this phone.
    var libraryID: String = ""
    var title: String = ""
    var artist: String = ""
    var duration: Double = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \CheckpointRecord.track)
    var checkpoints: [CheckpointRecord]? = []

    init(key: String, libraryID: String, title: String, artist: String, duration: Double) {
        self.key = key
        self.libraryID = libraryID
        self.title = title
        self.artist = artist
        self.duration = duration
        self.createdAt = Date()
    }

    var sortedCheckpoints: [CheckpointRecord] {
        (checkpoints ?? []).sorted { $0.time < $1.time }
    }
}

@Model
final class CheckpointRecord {
    var time: Double = 0
    var label: String = ""
    var createdAt: Date = Date()
    var track: TrackRecord?

    init(time: Double, label: String = "") {
        self.time = time
        self.label = label
        self.createdAt = Date()
    }
}

@MainActor
enum Persistence {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: TrackRecord.self, CheckpointRecord.self)
        } catch {
            fatalError("Could not open the checkpoint database: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}

@MainActor
enum CheckpointStore {
    static func track(forKey key: String) -> TrackRecord? {
        var descriptor = FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return (try? Persistence.context.fetch(descriptor))?.first
    }

    static func ensureTrack(for item: MPMediaItem) -> TrackRecord {
        let key = LibraryAccess.key(for: item)
        if let existing = track(forKey: key) {
            if existing.duration <= 0 { existing.duration = item.playbackDuration }
            existing.libraryID = String(item.persistentID)
            return existing
        }
        let track = TrackRecord(
            key: key,
            libraryID: String(item.persistentID),
            title: item.title ?? "Unknown Song",
            artist: item.artist ?? "Unknown Artist",
            duration: item.playbackDuration
        )
        Persistence.context.insert(track)
        save()
        return track
    }

    @discardableResult
    static func addCheckpoint(time: Double, to track: TrackRecord) -> CheckpointRecord {
        let checkpoint = CheckpointRecord(time: time)
        Persistence.context.insert(checkpoint)
        checkpoint.track = track
        save()
        return checkpoint
    }

    static func delete(_ checkpoint: CheckpointRecord) {
        Persistence.context.delete(checkpoint)
        save()
    }

    static func save() {
        do {
            try Persistence.context.save()
        } catch {
            DiagnosticsLog.shared.log("DB", "Save failed: \(error.localizedDescription)")
        }
    }
}
