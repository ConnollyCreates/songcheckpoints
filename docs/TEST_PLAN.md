# Parked-car test (about 30 minutes)

**Goal:** find out which approach turns a steering-wheel Next press into a checkpoint jump: **A** (our handlers), **B** (clone queue), or **Siri**. The app logs everything; you just press buttons and note what you hear.

## Before you go
- [ ] App installed (see README) and opened at least once. Library access allowed.
- [ ] Settings tab: Mode = **A+B (default)**, Activate audio session = **off**.
- [ ] Pick **one song** you know well and drop **3 checkpoints** about 30 seconds apart (e.g. 0:30, 1:00, 1:30). Do the same on a second song in a playlist.
- [ ] Test Log tab → **⋯ → Clear log**.
- [ ] In the car: connect over **Bluetooth** (note if your car uses **CarPlay** instead). Turn **Wi-Fi off** so you're on cellular.

Before each test, tap the **flag** in the Test Log tab (top left). It drops a numbered marker so I can find each test in the log.

## Tests

| # | Steps | Write down |
|---|---|---|
| 1 | Play the song with checkpoints. Phone **unlocked**, app on screen. Press **wheel Next** once. | Did it jump to a checkpoint, skip to another song, or do nothing? |
| 2 | Play from ~0:10. **Lock the phone**, wait 30s, press **wheel Next**. Then press **wheel Previous**. | Same, plus roughly how long until the jump (instant / ~1s / 2s+). |
| 3 | Locked. **Double-press Next quickly.** | Did it move two checkpoints? Any song skip? |
| 4 | Keep music playing with the phone **locked for 10 minutes** (drive around or just sit). Then press **wheel Next**. | Still jumps? |
| 5 | Start the **playlist** (2+ songs). Let song 1 reach its end **while locked**. | Did song 2 start on its own? Gap length? |
| 6 | Hold the wheel's **voice button**: "**Next drop in Checkpoints**". | Did Siri understand? Did it jump? How long did it take? |
| 7 | Trigger Siri from the wheel, dismiss it, then press **wheel Next**. | Music came back? Next still jumps? |

**Only if 1–2 didn't jump to checkpoints:**

| # | Steps | Write down |
|---|---|---|
| 8a | Settings → Mode **A only**. Repeat test 2. | |
| 8b | Settings → Mode **B only**. Repeat test 2. | |
| 8c | Mode **A only** + **Activate audio session on**. Repeat test 2. | |

**Optional:** AirPods press/double-tap (test 2 again), and CarPlay if your car has it.

## Send me the results
1. Test Log → **share icon** (top right) → Save to Files, AirDrop to your PC, or email it to yourself.
2. Upload the log file to our chat along with the notes from your tables above.

## What the log tells me
- `REMOTE: ✅ nextTrack handler fired` → **approach A works**. Cleanest result.
- `DETECT: System skip NEXT …` → iOS handled the button and **approach B** caught it.
- `HEART: ⚠️ No heartbeat for 300s` → iOS **suspended the app** while locked. That affects B and song-to-song playback.
- `QUEUE: iOS reports 1 queued entry` → this iPhone won't queue duplicate copies, so B can't work.
- `JUMP: … via Siri / Shortcut` → the Siri path worked.
