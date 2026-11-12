import Foundation
import MediaPlayer

/// Reads the user's Music library through the MediaPlayer framework.
/// This works without the paid MusicKit service: songs must be in the user's Library
/// (added from Apple Music, purchased, or synced).
enum LibraryAccess {
    static var status: MPMediaLibraryAuthorizationStatus {
        MPMediaLibrary.authorizationStatus()
    }

    static var statusLabel: String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }

    static func requestAuthorization() async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func allSongs() -> [MPMediaItem] {
        MPMediaQuery.songs().items ?? []
    }

    static func playlists() -> [MPMediaPlaylist] {
        (MPMediaQuery.playlists().collections as? [MPMediaPlaylist]) ?? []
    }

    static func item(libraryID: String) -> MPMediaItem? {
        guard let id = UInt64(libraryID) else { return nil }
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: NSNumber(value: id),
            forProperty: MPMediaItemPropertyPersistentID
        ))
        return query.items?.first
    }

    /// Prefer the Apple Music store ID (same on every device); fall back to the library ID.
    static func key(for item: MPMediaItem) -> String {
        let storeID = item.playbackStoreID
        if isUsableStoreID(storeID) { return "store:\(storeID)" }
        return "pid:\(item.persistentID)"
    }

    static func isUsableStoreID(_ id: String) -> Bool {
        !id.isEmpty && id != "0"
    }
}
