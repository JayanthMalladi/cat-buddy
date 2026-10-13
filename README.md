# Campus Cat

A tiny cat that lives on your Mac desktop. She rests quietly in the corner, wakes up when you click her, reacts, and now and then says something kind in a speech bubble. Everything is offline: no accounts, no internet, no AI at runtime.

## Download and open it

1. Go to the repository's **Releases** page and download **CampusCat.zip** from the "latest" release (or, from any run on the **Actions** tab, download the **CampusCat** artifact, which is a zip containing CampusCat.zip).
2. Double-click the zip to unpack it and drag **CampusCat.app** into **Applications**.
3. The first time only, macOS will block it because it isn't from the App Store or a paid developer account:
   - **macOS 14 (Sonoma) or older:** right-click (or Control-click) CampusCat.app, choose **Open**, then click **Open** in the dialog.
   - **macOS 15 (Sequoia) or newer:** double-click it, click **Done** on the warning, then open **System Settings → Privacy & Security**, scroll down to the message about CampusCat, click **Open Anyway**, and confirm with your password.
   - Alternative for either: open Terminal and run `xattr -dr com.apple.quarantine /Applications/CampusCat.app`, then open it normally.

After that it opens like any other app. It has no Dock icon; look for the paw print in the menu bar.

## Using it

- **Click the cat** to wake her up. Click again while she's awake for a reaction: a head tilt, a happy wiggle, a stretch, or a little walk.
- **Drag the cat** to move her anywhere. She remembers where you put her.
- Clicks on the empty space around her go straight through to whatever is behind.
- Left alone she goes back to resting, yawns now and then, and curls up to sleep after about ten minutes.
- **Menu bar paw:**
  - *Say Something* shows a message right away.
  - *Quiet Mode* turns off all speech bubbles.
  - *Bring Cat Back* moves her to the bottom-right corner if she ever gets lost off screen.
  - *Quit Campus Cat*.

To start it automatically, add it in **System Settings → General → Login Items**.

## Changing messages and timing

Both files are plain JSON inside the app (right-click CampusCat.app → *Show Package Contents* → `Contents/Resources`), and in this repo under `Resources/`.

- `messages.json`: lists of messages grouped by category. Add or remove lines freely. The cat waits at least a minute between messages, never repeats the last few, and on her own speaks only every 25–50 minutes.
- `animations.json`: one entry per state with `fps`, `loop`, the frame range (`start`, `end`), `offsetY` (points, to nudge a pose up or down) and `next` (the state after a one-shot animation).

Editing files inside the app breaks its signature; after editing, run `codesign --force --deep --sign - /Applications/CampusCat.app` in Terminal (or rebuild).

## Building

The app is a Swift package with no dependencies. GitHub Actions builds it on a macOS runner for every pull request and push to `main` (see `.github/workflows/build.yml`), and each push to `main` refreshes the "latest" release.

On a Mac with Xcode installed:

```sh
./scripts/build_app.sh      # makes build/CampusCat.app and build/CampusCat.zip
swift run                   # or run straight from the source tree
```

## Art

The frames in `Resources/Animations` come from the repaired 640×640 sprites. `tools/prepare_sprites.py` regenerates them: it keeps every second frame (12 fps), skips known glitches (the head pop in resting, the body jump at the end of happy, the clipped tail at the end of stretching), shifts every animation onto the same ground line, crops and scales to 427×367 px (shown at half size on Retina screens), and saves small palette PNGs.

```sh
python3 tools/prepare_sprites.py /path/to/sprites_repaired
```

## How it fits together

| File | What it does |
|---|---|
| `App.swift`, `AppDelegate.swift` | Startup and the menu bar item |
| `CatController.swift` | The state machine: which animation plays, clicks, idle timers, walking, messages |
| `CatWindow.swift` | The transparent always-on-top window, dragging, and pixel-accurate click-through |
| `Animation.swift` | Reads `animations.json`, loads frames, plays them |
| `SpeechBubble.swift`, `Messages.swift` | The bubble and the message picker |
