# Song Checkpoints

Save the moments in a song you care about (the drop, the chorus, a choreography cue) and jump between them with your **steering wheel**, **AirPods**, **Siri**, or the in-app buttons.

**Status: test build (v0.1).** The core question (can a steering-wheel Next press be turned into a checkpoint jump while Apple Music plays?) can only be answered on a real iPhone in a real car. This build is a working app *plus* a test harness that records exactly what iOS does. One car session tells us which approach v1 ships with. See [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md).

---

## Install it on your iPhone (Windows, free Apple ID)

No Mac and no $99 developer account needed for testing.

1. **Get the app file.** Open the repo's [**Releases → test-build**](../../releases/tag/test-build) and download `SongCheckpoints-unsigned.ipa`. Every push rebuilds it automatically on a cloud Mac (GitHub Actions).
2. **Install the tools on your PC:**
   - **iTunes from [apple.com/itunes](https://www.apple.com/itunes/download/win64)**. Sideloadly needs this version, not the Microsoft Store one.
   - **[Sideloadly](https://sideloadly.io)**.
3. **Plug in your iPhone** with a cable. Tap *Trust This Computer* on the phone.
4. **In Sideloadly:** drag in the `.ipa`, type your Apple ID, click **Start**, and enter your password and 2FA code when asked.
5. **On the iPhone:**
   - Settings → Privacy & Security → **Developer Mode** → On (the phone restarts).
   - Settings → General → **VPN & Device Management** → tap your Apple ID → **Trust**.
6. **Every 7 days** the free signature expires. Re-run Sideloadly with the newest `.ipa` (or turn on its auto-refresh).

### First run
1. In the **Music** app, add a few songs you know well to your **Library** (the + button). Settings → Music → **Sync Library** must be on.
2. Open **Checkpoints** → **Library** → *Allow Library Access* → tap a song.
3. On **Now Playing**, tap **Drop Checkpoint** at each moment you want to jump to. Tap a checkpoint to fine-tune it (±1s / ±0.1s, with instant replay).
4. Press **Next** on your wheel, AirPods, or lock screen, or say **"Hey Siri, next drop in Checkpoints."**

---

## How it works

| Piece | What it does |
|---|---|
| `Packages/CheckpointCore` | Pure Swift logic with unit tests: what Next/Previous should do (`JumpEngine`), rapid double-presses (`PressPredictor`), and spotting when iOS handled a button itself (`SkipDetector`). |
| `App/Player/PlayerService.swift` | Plays songs through Apple's *application queue player* and turns button presses into checkpoint jumps. |
| `App/Player/CheckpointIntents.swift` | Siri / Shortcuts / Back Tap actions: Next Drop, Previous Drop, Drop Checkpoint. |
| `App/Support/DiagnosticsLog.swift` | The **Test Log** tab: every button event, jump, queue change, interruption, and a 5-second heartbeat that shows if iOS suspended the app. |

### The three steering-wheel approaches (Settings → Steering-wheel test)

- **A: our button handlers.** The app registers its own Next/Previous handlers. Apple's forums suggest iOS may ignore these while its music player is playing, so this is the approach most likely to fail.
- **B: clone queue.** The same song is queued many times. A wheel Next makes iOS jump to an identical copy, and the app instantly seeks that copy to your next checkpoint. Expect a short glitch.
- **Siri / Back Tap.** These don't depend on the music player at all, so they're the backup if A and B both fail.

The default, **A+B**, runs both at once, and the Test Log shows which one actually fired.

### Why not MusicKit (yet)?
MusicKit, Apple's modern music API, needs the paid Apple Developer Program. This build uses the older MediaPlayer framework, which plays songs in your Library for free and is the same player the steering-wheel question is about. When you enroll ($99/yr), we can add Apple Music catalog search, TestFlight, and the App Store.

---

## Development

- **Logic tests:** `swift test --package-path Packages/CheckpointCore` (works on macOS or Linux).
- **Cloud build:** `.github/workflows/build.yml` runs the tests, generates the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen), builds an unsigned iPhone app, and publishes it to the `test-build` release.
- **On a Mac:** `brew install xcodegen && xcodegen generate && open SongCheckpoints.xcodeproj`.

## Road to v1
1. **Now:** car test → pick the trigger approach that works (A, B, or Siri-first).
2. **v0.2:** remove the losing approaches, polish song-to-song playback, add a lock-screen-friendly "driving mode" screen.
3. **v1:** enroll in the Apple Developer Program → TestFlight → MusicKit catalog search → iCloud sync → App Store.
