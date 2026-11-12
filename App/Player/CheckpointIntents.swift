import AppIntents

// Siri / Shortcuts / Back Tap triggers. These run inside the app without opening it,
// so they work while the phone is locked. In the car: hold the wheel's voice button
// and say "Next drop in Checkpoints".

struct NextCheckpointIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Checkpoint"
    static let description = IntentDescription("Jump to the next checkpoint in the song that's playing.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        PlayerService.shared.ensureStarted()
        PlayerService.shared.nextCheckpoint(source: .siri)
        return .result()
    }
}

struct PreviousCheckpointIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Checkpoint"
    static let description = IntentDescription("Jump back to the previous checkpoint in the song that's playing.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        PlayerService.shared.ensureStarted()
        PlayerService.shared.previousCheckpoint(source: .siri)
        return .result()
    }
}

struct DropCheckpointIntent: AppIntent {
    static let title: LocalizedStringResource = "Drop Checkpoint"
    static let description = IntentDescription("Save a checkpoint at the current spot in the song that's playing.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        PlayerService.shared.ensureStarted()
        PlayerService.shared.dropCheckpoint(source: .siri)
        return .result()
    }
}

struct CheckpointShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextCheckpointIntent(),
            phrases: [
                "Next drop in \(.applicationName)",
                "Skip ahead in \(.applicationName)",
                "\(.applicationName) next"
            ],
            shortTitle: "Next Drop",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: PreviousCheckpointIntent(),
            phrases: [
                "Previous drop in \(.applicationName)",
                "Go back in \(.applicationName)",
                "\(.applicationName) back"
            ],
            shortTitle: "Previous Drop",
            systemImageName: "backward.end.fill"
        )
        AppShortcut(
            intent: DropCheckpointIntent(),
            phrases: [
                "Mark this in \(.applicationName)",
                "Drop a checkpoint in \(.applicationName)"
            ],
            shortTitle: "Drop Checkpoint",
            systemImageName: "mappin.and.ellipse"
        )
    }
}
