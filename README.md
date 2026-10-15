# Vrinda's Cat

A tiny cat that lives on your Mac desktop. She sleeps quietly in the corner, wakes up and does something cute when you rest the pointer on her, and every so often says something kind in a speech bubble. No accounts and no AI at runtime. The only things she fetches from the internet are her messages and app updates.

## Download and open it

1. Go to the repository's **Releases** page and download **VrindasCat.zip** from the "latest" release (or, from any run on the **Actions** tab, download the **VrindasCat** artifact, which is a zip containing VrindasCat.zip).
2. Double-click the zip to unpack it and drag **Vrinda's Cat.app** into **Applications**.
3. The first time only, macOS will block it because it isn't from the App Store or a paid developer account:
   - **macOS 14 (Sonoma) or older:** right-click (or Control-click) Vrinda's Cat.app, choose **Open**, then click **Open** in the dialog.
   - **macOS 15 (Sequoia) or newer:** double-click it, click **Done** on the warning, then open **System Settings → Privacy & Security**, scroll down to the message about Vrinda's Cat, click **Open Anyway**, and confirm with your password.
   - Alternative for either: open Terminal and run `xattr -dr com.apple.quarantine "/Applications/Vrinda's Cat.app"`, then open it normally.

After that it opens like any other app. It has no Dock icon; look for the paw print in the menu bar.

You only do this once: from then on the app **updates itself** (see below).

## Using it

- She sleeps curled up by default.
- **Rest the pointer on her** while she sleeps: she wakes up for one random action (stretch, yawn, head tilt, happy wiggle, sitting up, or a short rest) and goes back to sleep when it's done. Leaving the pointer on her won't start another one; move it away from her and back for that.
- She also says a message when you hover or click, but at most once every 2 minutes. Inside that window she still does her action, just quietly.
- **Drag the cat** to move her anywhere. She remembers where you put her.
- Clicks on the empty space around her go straight through to whatever is behind.
- **Every 5 minutes** she wakes up by herself and walks to the other side of the screen, then curls up to sleep there. Walks are silent, and hovering or clicking does nothing until she's asleep again. If she's in the middle of something when it's time, she finishes it first.
- Every so often (every 15 minutes by default) she rests and says a random message on her own.
- **Reminders** come on their own schedule: drink water every hour, stretch every 90 minutes (she stretches with you), and a snack check every 4 hours.
- **Menu bar paw:**
  - *Say Something* shows a message right away.
  - *Quiet Mode* stops everything she says on her own (hover, timed messages and reminders). Clicking her still gets you one.
  - *Water & Stretch Reminders* turns the reminders on or off.
  - *Messages* sets how often she talks: every 5, 15 or 30 minutes, or every hour.
  - *Size* makes her Small, Medium, Large or Extra Large (remembered between launches).
  - *Bring Cat Back* moves her to the bottom-right corner if she ever gets lost off screen.
  - *Set Messages Link…* points her at your messages sheet (see below).
  - *Check for Updates* looks for a new build right away; the line under it shows which build is running.
  - *Quit Vrinda's Cat*.

To start it automatically, add it in **System Settings → General → Login Items**.

## Updates and new messages

- **Messages:** the app downloads its messages when it starts and then every hour, so new ones reach her within the hour without a new build. A broken or empty list is ignored and she keeps the messages she has; the last good copy is kept for when the Mac is offline. Where they come from:
  - **A Google Sheet (recommended):** put one message per row in column A (a header row saying "Message" is fine). Click **Share → General access → Anyone with the link → Viewer** and copy the link. On her Mac, choose **Set Messages Link…** from the paw menu and paste it. The link is saved only in that Mac's settings, never in the app or this repo, so the public download doesn't reveal it, and it survives updates. A Drive text file (one message per line) works the same way.
  - **Otherwise:** `Resources/messages.json` on the `main` branch, which anyone can read.
- **The app itself:** every merge to `main` builds a new release. About 30 seconds after launch, and then every hour, the app checks the "latest" release; if it was built from a different commit, it downloads it, swaps itself for the new version and reopens (she disappears for a second or two). This only works when the app is in Applications. The first update after installing may make macOS ask whether Vrinda's Cat can update apps; allow it.

## Changing messages and timing

All three files are plain JSON inside the app (right-click Vrinda's Cat.app → *Show Package Contents* → `Contents/Resources`), and in this repo under `Resources/`.

- `messages.json`: lists of messages grouped by category. Add or remove lines freely. The cat never repeats the last few, and talks on the interval chosen in the menu.
- `reminders.json`: each reminder's text, how often it comes (`everyMinutes`), and optionally an `animation` to play with it.
- `animations.json`: one entry per state with `fps`, `loop`, the frame range (`start`, `end`), `offsetY` (points, to nudge a pose up or down).

Editing files inside the app breaks its signature; after editing, run `codesign --force --deep --sign - "/Applications/Vrinda's Cat.app"` in Terminal (or rebuild).

## Building

The app is a Swift package with no dependencies. GitHub Actions builds it on a macOS runner for every pull request and push to `main` (see `.github/workflows/build.yml`), and each push to `main` refreshes the "latest" release.

On a Mac with Xcode installed:

```sh
./scripts/build_app.sh      # makes "build/Vrinda's Cat.app" and build/VrindasCat.zip
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
| `CatController.swift` | The state machine: which animation plays, hover, walking, messages, reminders |
| `CatWindow.swift` | The transparent always-on-top window, dragging, and pixel-accurate click-through |
| `Animation.swift` | Reads `animations.json`, loads frames, plays them |
| `SpeechBubble.swift`, `Messages.swift` | The bubble and the message picker |
