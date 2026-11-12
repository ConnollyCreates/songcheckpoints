import SwiftUI
import MediaPlayer
import CheckpointCore

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerService
    @State private var editing: CheckpointRecord?

    var body: some View {
        NavigationStack {
            Group {
                if let item = player.currentItem {
                    content(for: item)
                } else {
                    ContentUnavailableView(
                        "Nothing playing",
                        systemImage: "music.note",
                        description: Text("Pick a song or playlist in the Library tab.")
                    )
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { checkpoint in
                CheckpointEditorView(checkpoint: checkpoint)
                    .environmentObject(player)
            }
        }
    }

    @ViewBuilder
    private func content(for item: MPMediaItem) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? "Unknown Song")
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(item.artist ?? "Unknown Artist")
                        .foregroundStyle(.secondary)
                    Text("Song \(player.sessionIndex + 1) of \(player.session.count) · Mode \(player.activeMode.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                TimelineBar(
                    position: player.position,
                    duration: player.duration,
                    checkpoints: player.checkpointRecords.map(\.time)
                )
                .frame(height: 28)

                HStack {
                    Text(TimeFormat.string(player.position))
                    Spacer()
                    Text(TimeFormat.string(player.duration, tenths: false))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                controls
                    .padding(.vertical, 6)

                Button {
                    player.dropCheckpoint(source: .app)
                } label: {
                    Label("Drop Checkpoint", systemImage: "mappin.and.ellipse")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .listRowSeparator(.hidden)
            }

            Section("Last action") {
                Text(player.lastAction)
                    .font(.footnote.monospaced())
            }

            Section {
                if player.checkpointRecords.isEmpty {
                    Text("No checkpoints yet. Tap Drop Checkpoint when you hear a moment you want to jump to. With none saved, Next skips ahead \(Int(AppSettings.skipInterval))s.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(player.checkpointRecords) { checkpoint in
                        Button {
                            editing = checkpoint
                        } label: {
                            HStack {
                                Image(systemName: "mappin")
                                    .foregroundStyle(.tint)
                                Text(TimeFormat.string(checkpoint.time))
                                    .font(.body.monospacedDigit())
                                if !checkpoint.label.isEmpty {
                                    Text(checkpoint.label)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete(perform: deleteCheckpoints)
                }
            } header: {
                Text("Checkpoints")
            } footer: {
                if !player.checkpointRecords.isEmpty {
                    Text("Tap to fine-tune. Swipe left to delete.")
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            controlButton("backward.end.fill", label: "Previous song") { player.skipSong(by: -1) }
            controlButton("gobackward", label: "Previous checkpoint") { player.previousCheckpoint(source: .app) }
            controlButton(player.isPlaying ? "pause.circle.fill" : "play.circle.fill", label: "Play or pause", size: 52) {
                player.togglePlayPause()
            }
            controlButton("goforward", label: "Next checkpoint") { player.nextCheckpoint(source: .app) }
            controlButton("forward.end.fill", label: "Next song") { player.skipSong(by: 1) }
        }
        .buttonStyle(.borderless)
    }

    private func controlButton(_ symbol: String, label: String, size: CGFloat = 26, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .accessibilityLabel(label)
    }

    private func deleteCheckpoints(at offsets: IndexSet) {
        let doomed = offsets.map { player.checkpointRecords[$0] }
        for checkpoint in doomed {
            CheckpointStore.delete(checkpoint)
        }
        player.reloadCheckpoints()
    }
}

/// Progress bar with a tick for every checkpoint.
struct TimelineBar: View {
    let position: Double
    let duration: Double
    let checkpoints: [Double]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let total = max(duration, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 6)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: width * min(max(position / total, 0), 1), height: 6)
                ForEach(Array(checkpoints.enumerated()), id: \.offset) { _, time in
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 3, height: 22)
                        .offset(x: width * min(max(time / total, 0), 1) - 1.5)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}
