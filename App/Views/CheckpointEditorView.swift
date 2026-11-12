import SwiftUI
import SwiftData
import CheckpointCore

struct CheckpointEditorView: View {
    @Bindable var checkpoint: CheckpointRecord
    @EnvironmentObject private var player: PlayerService
    @Environment(\.dismiss) private var dismiss
    @State private var deleteOnClose = false

    private var songDuration: Double? {
        let value = checkpoint.track?.duration ?? player.duration
        return value > 0 ? value : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(TimeFormat.string(checkpoint.time))
                        .font(.system(size: 48, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)

                    HStack {
                        nudgeButton(-1, title: "−1s")
                        nudgeButton(-0.1, title: "−0.1s")
                        nudgeButton(0.1, title: "+0.1s")
                        nudgeButton(1, title: "+1s")
                    }

                    Button {
                        player.preview(at: checkpoint.time)
                    } label: {
                        Label("Preview from 2s before", systemImage: "play.fill")
                    }

                    Button {
                        checkpoint.time = CheckpointMath.clamp(player.position, duration: songDuration)
                        player.preview(at: checkpoint.time, leadIn: 0.5)
                    } label: {
                        Label("Move to current position", systemImage: "scope")
                    }
                } footer: {
                    Text("Each nudge replays from just before the checkpoint so you can hear where it lands.")
                }

                Section("Label (optional)") {
                    TextField("e.g. Drop, Chorus, Verse 2", text: $checkpoint.label)
                }

                Section {
                    Button("Delete Checkpoint", role: .destructive) {
                        deleteOnClose = true
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Checkpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear {
                if deleteOnClose {
                    CheckpointStore.delete(checkpoint)
                } else {
                    CheckpointStore.save()
                }
                player.reloadCheckpoints()
            }
        }
    }

    private func nudgeButton(_ delta: Double, title: String) -> some View {
        Button(title) {
            checkpoint.time = CheckpointMath.nudge(checkpoint.time, by: delta, duration: songDuration)
            player.preview(at: checkpoint.time, leadIn: 1)
        }
        .buttonStyle(.bordered)
        .font(.callout.monospacedDigit())
        .frame(maxWidth: .infinity)
    }
}
