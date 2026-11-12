import SwiftUI
import SwiftData
import MediaPlayer

struct LibraryView: View {
    var onStartPlayback: () -> Void

    @EnvironmentObject private var player: PlayerService
    @Query(sort: \TrackRecord.createdAt, order: .reverse) private var tracks: [TrackRecord]

    @State private var status = LibraryAccess.status
    @State private var songs: [MPMediaItem] = []
    @State private var playlists: [MPMediaPlaylist] = []
    @State private var search = ""
    @State private var scope: Scope = .songs
    @State private var loaded = false

    enum Scope: String, CaseIterable, Identifiable {
        case songs = "Songs"
        case playlists = "Playlists"
        case saved = "Has Checkpoints"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch status {
                case .authorized:
                    library
                case .notDetermined:
                    requestAccess
                default:
                    ContentUnavailableView(
                        "No library access",
                        systemImage: "lock.fill",
                        description: Text("Turn on Media & Apple Music for Checkpoints in the iPhone Settings app.")
                    )
                }
            }
            .navigationTitle("Library")
            .task { loadIfNeeded() }
        }
    }

    private var requestAccess: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.house")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Checkpoints plays songs from your Music library.\nAdd songs to your Library in the Music app first.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Allow Library Access") {
                Task { @MainActor in
                    status = await LibraryAccess.requestAuthorization()
                    DiagnosticsLog.shared.log("APP", "Library access → \(LibraryAccess.statusLabel)")
                    loadIfNeeded()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var library: some View {
        List {
            Picker("Show", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            switch scope {
            case .songs:
                if filteredSongs.isEmpty {
                    emptyNote
                }
                ForEach(Array(filteredSongs.enumerated()), id: \.element.persistentID) { index, item in
                    Button {
                        start(filteredSongs, at: index)
                    } label: {
                        SongRow(
                            title: item.title ?? "Unknown Song",
                            artist: item.artist ?? "Unknown Artist",
                            checkpointCount: checkpointCounts[LibraryAccess.key(for: item)] ?? 0
                        )
                    }
                    .foregroundStyle(.primary)
                }

            case .playlists:
                ForEach(filteredPlaylists, id: \.persistentID) { playlist in
                    Button {
                        start(playlist.items, at: 0)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(playlist.name ?? "Playlist")
                            Text("\(playlist.count) songs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

            case .saved:
                if savedTracks.isEmpty {
                    Text("Songs you add checkpoints to show up here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(savedTracks) { track in
                    Button {
                        startSaved(track, in: savedTracks)
                    } label: {
                        SongRow(title: track.title, artist: track.artist, checkpointCount: track.checkpoints?.count ?? 0)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "Search title or artist")
        .refreshable { reload() }
    }

    private var emptyNote: some View {
        Text(search.isEmpty
             ? "No songs found. In the Music app, add songs to your Library (and turn on Settings → Music → Sync Library), then pull down to refresh."
             : "No matches.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var filteredSongs: [MPMediaItem] {
        guard !search.isEmpty else { return songs }
        return songs.filter { matches($0.title ?? "", $0.artist ?? "") }
    }

    private var filteredPlaylists: [MPMediaPlaylist] {
        guard !search.isEmpty else { return playlists }
        return playlists.filter { ($0.name ?? "").localizedCaseInsensitiveContains(search) }
    }

    private var savedTracks: [TrackRecord] {
        tracks.filter { !($0.checkpoints ?? []).isEmpty && matches($0.title, $0.artist) }
    }

    private var checkpointCounts: [String: Int] {
        Dictionary(tracks.map { ($0.key, $0.checkpoints?.count ?? 0) }, uniquingKeysWith: +)
    }

    private func matches(_ title: String, _ artist: String) -> Bool {
        search.isEmpty
            || title.localizedCaseInsensitiveContains(search)
            || artist.localizedCaseInsensitiveContains(search)
    }

    private func loadIfNeeded() {
        guard status == .authorized, !loaded else { return }
        reload()
    }

    private func reload() {
        songs = LibraryAccess.allSongs()
        playlists = LibraryAccess.playlists()
        loaded = true
        DiagnosticsLog.shared.log("APP", "Library loaded: \(songs.count) songs, \(playlists.count) playlists")
    }

    private func start(_ items: [MPMediaItem], at index: Int) {
        guard !items.isEmpty else { return }
        player.play(items: items, startAt: index)
        onStartPlayback()
    }

    private func startSaved(_ track: TrackRecord, in list: [TrackRecord]) {
        let items = list.compactMap { LibraryAccess.item(libraryID: $0.libraryID) }
        guard let item = LibraryAccess.item(libraryID: track.libraryID),
              let index = items.firstIndex(where: { $0.persistentID == item.persistentID }) else {
            DiagnosticsLog.shared.log("APP", "Couldn't find \"\(track.title)\" in this phone's library")
            return
        }
        start(items, at: index)
    }
}

struct SongRow: View {
    let title: String
    let artist: String
    let checkpointCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if checkpointCount > 0 {
                Label("\(checkpointCount)", systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
