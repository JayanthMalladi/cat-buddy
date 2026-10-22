# Desktop Cat

A small pixel cat that lives on a Mac desktop and keeps someone company from far away.

She sleeps in a corner of the screen and wakes up when you rest the pointer on her. Now and then she walks across the screen or says something kind in a speech bubble. She also keeps a to-do sticky note and checks in on it during the day. The person who set her up can edit her messages and send live nudges from a Google Sheet, and she updates herself from this repo's releases.

There is no account, no server, no tracking and no AI running inside the app. It only fetches her messages, the sheet's Control tab and app updates.

> The app currently ships as **Narasimha.app** (its display name); the project, download and data folder are called Desktop Cat.

## Why it exists

Desktop Cat started as a gift for someone in a long-distance relationship. The goal is a small, warm presence on their screen that the sender can keep tending day to day without shipping a new build. That shaped the design:

- **It has to be cute and quiet.** It is one hand-animated cat with eight poses. She stays out of the way, mouse clicks pass through everything except the cat herself, and Quiet Mode silences everything she would say unprompted.
- **The sender needs a remote control, not a backend.** The cat's messages, nudges and check-in times come from an ordinary Google Sheet that only the sender edits.
- **Installing and updating must happen once, by someone who isn't technical.** She updates herself from GitHub releases, with no App Store and no developer account.
- **The repo is public, so nothing personal lives in it.** The sheet link is pasted on the recipient's Mac and stays only in that Mac's settings.

## What she does

| | |
|---|---|
| **Sleeps and reacts** | She curls up asleep by default. Resting the pointer on her wakes her for one random action (stretch, yawn, head tilt, happy wiggle, sit up, short rest), and she goes back to sleep afterwards. The pointer has to leave and come back before she does another one. |
| **Walks** | Every 5 minutes she gets up, walks silently to the far side of the screen and curls up there. |
| **Talks** | She says a random message every 5, 15, 30 or 60 minutes (chosen in the menu). Hovering or clicking also gets a message, at most once every 2 minutes. |
| **Reminds** | Water every hour, a stretch every 90 minutes (she stretches too), a snack every 4 hours. |
| **To-do note** | A yellow pixel sticky note sits beside her and follows her around. Add tasks any time, click one to tick it off (she celebrates and a paw print fills in), or right-click to delete. Unfinished tasks carry over to the next day. |
| **Check-ins** | At 11:00, 15:00 and 19:00 she asks about the oldest unfinished task by name; the last one of the day is a "last call". |
| **Nudges** | A line typed into the sheet's Control tab shows up within a minute in a pinned pink bubble. She dances until it's clicked. |
| **Updates herself** | She checks the "latest" release 30 seconds after launch and then every hour. If there is a newer build, she swaps herself for it and reopens. |

## Install

1. Download **DesktopCat.zip** from the "latest" release on the **Releases** page. Unzip it and drag **Narasimha.app** into **Applications**.
2. The first time only, macOS blocks it because it isn't from the App Store or a paid developer account:
   - **macOS 14 or older:** right-click the app, choose **Open**, then click **Open** again.
   - **macOS 15 or newer:** open it, click **Done** on the warning, then go to **System Settings → Privacy & Security**, click **Open Anyway** next to the message about the app, and confirm with your password.
   - **Either version:** run `xattr -dr com.apple.quarantine "/Applications/Narasimha.app"` in Terminal.
3. To have her start with the Mac, add the app under **System Settings → General → Login Items**.

The app has no Dock icon. Look for the paw print in the menu bar. After this first install, every update arrives on its own.

### The paw menu

| Item | What it does |
|---|---|
| To-Do Note | Shows or tucks away the sticky note |
| Say Something | A message right now |
| Quiet Mode | Stops everything she says on her own; clicking her still gets one |
| Water & Stretch Reminders | Turns the reminders on or off |
| Messages | How often she talks on her own |
| Size | Small, Medium, Large or Extra Large |
| Bring Cat Back | Moves her to the bottom-right corner if she gets lost |
| Set Messages Link… | Pastes in the Google Sheet link (see below) |
| Check for Updates | Looks for a new build now; the line under it shows the running build |

## The Google Sheet (remote control)

The sheet is the only thing the sender has to maintain.

1. Make a Google Sheet. In the first tab, put one message per row in column A (a header row saying "Message" is fine).
2. Click **Share → General access → Anyone with the link → Viewer**, and copy the link.
3. On the cat's Mac, choose **Set Messages Link…** and paste it. The link is saved only in that Mac's settings, never in the app or this repo, and it survives updates.

Add a second tab named **Control** with a name in column A and a value in column B:

| A | B |
|---|---|
| Nudge | Go finish that lab report, I believe in you! |
| Check-in times | 11:00, 15:00, 19:00 |

- **Nudge:** each new line is shown once, in a pinned bubble, even in Quiet Mode. To send the same words again, change them slightly.
- **Check-in times:** comma-separated times in her time zone, such as `10am, 2pm, 8pm` or `9:30, 13:00, 21:00`. Clear the cell to go back to the defaults.

She re-reads the sheet every minute. A broken, empty or unshared sheet is ignored, and she keeps what she had. The last good copy is cached for when the Mac is offline. Without a sheet she uses the generic lines in `Resources/messages.json`.

## How it works

```
Google Sheet ──(CSV, every minute)──▶ RemoteMessages, RemoteControl ─┐
                                                                     ▼
paw menu, hover, clicks, timers ────────────────────────▶ CatController
                                                          │    │    │
                                       CatPanel + sprites ┘    │    └ SpeechBubble
                                                   TodoList + TodoNote

GitHub release "latest" (version.txt + DesktopCat.zip) ──(hourly)──▶ Updater
```

- **The window.** The cat is a borderless, transparent, always-on-top panel that never takes focus. Several times a second the app checks the pixel under the pointer against the current animation frame, so only the cat herself catches the mouse.
- **Animation.** There are eight states (`curledSleeping`, `stretching`, `yawning`, `curious`, `happy`, `awake`, `resting`, `walking`). `animations.json` maps each one to a folder of PNG frames, a frame rate, whether it loops, and a vertical offset. A one-shot animation returns to sleep when it ends.
- **The state machine** (`CatController`) decides what plays next from hover, clicks, timers, walks, reminders, check-ins and nudges. A sequence always plays to the end, and nothing starts during a walk.
- **The to-do note** is a separate non-activating panel attached to the cat window, so it moves with her and can take typing without bringing the app to the front. Tasks are saved as JSON in `~/Library/Application Support/Desktop Cat/`.
- **Remote control.** A pasted sheet link is turned into CSV export URLs: the first tab supplies messages, and a `gviz` query for the Control tab supplies nudges and check-in times. Nothing is ever written back.
- **Self-update.** CI stamps the commit into `Info.plist` and publishes `version.txt` next to the zip. When the two differ, the app downloads the zip and unpacks it with `ditto`. It checks the bundle id and the code signature, clears the quarantine flag, and swaps the app bundle in place. A small shell loop then reopens it once the old process has quit. It uses plain release download links rather than the GitHub API, so it never hits API rate limits.

## Building and testing

The app is a Swift package (AppKit, macOS 12+) with no dependencies.

```sh
./scripts/build_app.sh    # universal, ad-hoc signed build/Narasimha.app and build/DesktopCat.zip
swift run                 # run straight from the source tree
```

A Mac isn't needed to work on it. GitHub Actions (`.github/workflows/build.yml`) runs on a macOS runner for every pull request and push:

1. Builds the app.
2. Launches the real binary and drives it with `tools/ui_check.swift`, which uses synthetic mouse events to hover, drag, try dragging from a transparent corner and wait for a walk. It asserts the results and saves screenshots.
3. Loads a sample to-do list, a nudge and a check-in from a local file, and checks that all three ran.
4. Pretends a copy is an old build, serves the new build as a local "release", and checks that the copy replaces itself and reopens.
5. On `main`, publishes the "latest" release.

Screenshots from every run are uploaded as the **screenshots** artifact.

Hidden settings exist for testing. Set them with `defaults write com.campuscat.buddy <key> <value>`.

| Key | Effect |
|---|---|
| `walkEverySeconds` | Time between walks (default 300) |
| `autoUpdate` | `false` stops self-updates |
| `updateFeed` | Folder or URL to read `version.txt` and the zip from |
| `controlFeed` | URL of a CSV to use instead of the sheet's Control tab |
| `todoNoteOpen` | Whether the note is showing |
| `checkInTimes` | Check-in times, in the same format as the sheet |

## Project layout

| Path | What it is |
|---|---|
| `Sources/CampusCat/App.swift`, `AppDelegate.swift` | Startup and the paw menu |
| `CatController.swift` | The state machine: animations, hover, walking, messages, reminders, check-ins, nudges |
| `CatWindow.swift` | The transparent window, dragging and pixel-accurate click-through |
| `Animation.swift` | Reads `animations.json`, loads frames, plays them |
| `SpeechBubble.swift`, `Messages.swift` | The bubble (normal and pinned) and the message picker |
| `Todos.swift`, `TodoNote.swift` | The to-do list, check-in times and the sticky note |
| `RemoteMessages.swift`, `RemoteControl.swift` | Reading the sheet |
| `Updater.swift` | Self-update from GitHub releases |
| `Resources/` | Frames, `animations.json`, `messages.json`, `reminders.json` |
| `scripts/build_app.sh`, `scripts/Info.plist` | Packaging and signing |
| `tools/ui_check.swift` | The CI UI test |
| `tools/prepare_sprites.py` | Rebuilds the frames from the source sprites |

The executable and bundle id are still `CampusCat` and `com.campuscat.buddy` from the first prototype. They stay as they are because installed copies match updates by bundle id and keep their settings under it.

### Customizing without code

The three JSON files in `Resources/` (also inside the app under `Contents/Resources`) control the built-in content:

- `messages.json` holds built-in lines grouped by category. The cat avoids repeating the last few.
- `reminders.json` gives each reminder's text, how often it comes (`everyMinutes`) and an optional `animation`.
- `animations.json` gives each state's `fps`, `loop`, frame range (`start`, `end`) and `offsetY`.

Editing them inside an installed app breaks its signature. Re-sign it with `codesign --force --deep --sign - "/Applications/Narasimha.app"`, or rebuild.

### Art pipeline

The frames come from 640×640 sprite sheets: eight animations, 96 frames each. `tools/prepare_sprites.py` processes them:

- keeps every second frame (12 fps)
- skips known glitches
- puts every animation on the same ground line
- crops and scales to 427×367 px (shown at half size on Retina screens)
- writes small palette PNGs

```sh
python3 tools/prepare_sprites.py /path/to/sprites
```

## Limits today

- **macOS only.** The window and update tricks are AppKit-specific.
- **Ad-hoc signed.** The Gatekeeper step is needed once per Mac. Notarization would remove it but needs a paid developer account.
- **One sender, one cat.** The sheet is a single shared remote: there are no per-user identities, and nothing goes back from the cat to the sender.
- **Plain polling.** Nudges arrive within about a minute, and updates within an hour.
- **Link-shared sheet.** Anyone who has the link can read it, so it shouldn't hold anything more private than what she'd see anyway.
