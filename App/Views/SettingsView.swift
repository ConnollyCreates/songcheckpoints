import SwiftUI
import AppIntents

struct SettingsView: View {
    @EnvironmentObject private var player: PlayerService
    @AppStorage(SettingsKey.triggerMode) private var mode = TriggerMode.both.rawValue
    @AppStorage(SettingsKey.cloneCount) private var cloneCount = 40
    @AppStorage(SettingsKey.activateAudioSession) private var activateAudioSession = false
    @AppStorage(SettingsKey.skipInterval) private var skipInterval = 15.0
    @AppStorage(SettingsKey.reactionOffset) private var reactionOffset = 0.3

    private var selectedMode: TriggerMode {
        TriggerMode(rawValue: mode) ?? .both
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(TriggerMode.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    Text(selectedMode.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if selectedMode.usesClones {
                        Stepper("Queued copies: \(cloneCount)", value: $cloneCount, in: 10...100, step: 10)
                    }
                    Toggle("Activate audio session", isOn: $activateAudioSession)
                } header: {
                    Text("Steering-wheel test")
                } footer: {
                    Text("Changing these reloads the current song at the same spot. Leave the audio session off unless the test plan says to flip it.")
                }

                Section("Checkpoints") {
                    Stepper("Next with no checkpoints: +\(Int(skipInterval))s", value: $skipInterval, in: 5...60, step: 5)
                    Stepper("Drop reaction offset: \(String(format: "%.1f", reactionOffset))s", value: $reactionOffset, in: 0...1, step: 0.1)
                }

                Section {
                    SiriTipView(intent: NextCheckpointIntent())
                    Text("Also try: “Previous drop in Checkpoints”, “Mark this in Checkpoints”. To use a double-tap on the back of the phone: Settings → Accessibility → Touch → Back Tap → Next Drop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Siri & Back Tap")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                    LabeledContent("Player", value: "MediaPlayer application queue")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: mode) { player.applyTriggerMode(reloadSong: true) }
            .onChange(of: cloneCount) { player.applyTriggerMode(reloadSong: true) }
            .onChange(of: activateAudioSession) { player.applyTriggerMode(reloadSong: true) }
        }
    }
}
