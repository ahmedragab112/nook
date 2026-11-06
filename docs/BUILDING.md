# Building Nook

Nook is a plain Swift package — there is no Xcode project to open and no
dependencies to resolve.

## Requirements

| | |
| --- | --- |
| macOS | 13 Ventura or later (built and tested on macOS 27) |
| Swift | 5.10 toolchain |
| Xcode Command Line Tools | `xcode-select --install` — provides `swift`, `clang`, `codesign` |
| Architecture | The release script builds **arm64** (Apple Silicon) |

The MediaRemote adapter is compiled with `clang` as a universal binary; the app
binary itself is arm64. To build on an Intel Mac, edit `Scripts/build_app.sh` and
replace `--arch arm64` with `--arch x86_64`.

## Build and install

```bash
git clone https://github.com/ahmedragab112/nook.git
cd nook
./Scripts/build_app.sh
cp -R Nook.app /Applications/
open /Applications/Nook.app
```

`Scripts/build_app.sh` does four things:

1. `swift build -c release --arch arm64`
2. Assembles `Nook.app` from `.build/release/Nook`, `Support/Info.plist` and the icon
3. Rebuilds `Support/MediaRemoteAdapter` and copies the adapter and framework into
   `Contents/Resources`
4. Ad-hoc signs the executable and the bundle

Ad-hoc signing is enough for local use. Nook is not notarized, so if you copy the
app to another Mac, Gatekeeper may require **System Settings → Privacy & Security →
Open Anyway** on first launch.

## Run from the command line

```bash
swift run Nook
```

Running the raw executable works for development, but macOS associates
permission prompts (Calendar, Reminders, Camera, Screen Recording) with the app
bundle identity. For realistic permission testing, build and launch `Nook.app`.

## Developer flags

Nook ships with a small rendering pipeline so documentation and visual checks
never expose real data.

| Flag | Effect |
| --- | --- |
| `--demo` | Fills media, calendar and notes with sample content; disables permission prompts |
| `--render=<dir>` | Writes every enabled panel to `<dir>/<tab>.png`, then quits |
| `--snapshot=<file>` | Captures the expanded media panel to a PNG |
| `--snapshot-mini=<file>` | Captures the collapsed now-playing strip on transparency |

Examples:

```bash
.build/release/Nook --render=/tmp/nook-shots --demo
.build/release/Nook --snapshot=/tmp/media.png --demo
.build/release/Nook --snapshot-mini=/tmp/strip.png --demo
```

`RunMode.isRendering` is true for any of the snapshot/render flags, and
`RunMode.isDemo` is true only for `--demo`. Services check these flags instead of
talking to EventKit, the camera or MediaRemote.

## Where data lives

```
~/Library/Application Support/Nook/
├── scratch.txt      # Notes
├── shortcuts.json   # Shortcuts
├── weather.json     # Last forecast cache
└── Shelf/           # Files dropped on the Shelf
```

Preferences are stored under the bundle identifier `com.ahmedragab.nook` in
`UserDefaults`. Clipboard history is memory-only.

## Troubleshooting

**The notch does not appear.**
Make sure Nook is running (`pgrep -fl Nook`). It is an accessory app, so it has
no Dock icon; open it again from Finder or `/Applications`.

**Nothing happens on hover.**
Check that **Open on hover** is enabled in Settings, and that **Hide in
fullscreen spaces** is not hiding the panel in your current Space.

**Calendar or Reminders is empty.**
Open the panel and grant access. If you previously declined, re-enable it in
**System Settings → Privacy & Security → Calendars / Reminders**. Ad-hoc signed
builds get a fresh identity when rebuilt, so macOS can ask again.

**The mirror is black.**
Grant Camera access, then close and reopen the Mirror tab.

**The colour picker cannot sample.**
Grant **Screen Recording** access and relaunch Nook.

**Now playing is empty.**
Nook reads MediaRemote through the bundled adapter. Start playback in Music,
Spotify or a browser, then hover the notch. Some apps only publish metadata
while they are the active player.

**The hotkey does nothing.**
Another app may own <kbd>⌃</kbd><kbd>⌥</kbd><kbd>N</kbd>. Pick a different
combination in Settings → Shortcut.

**The window is misaligned on an external display.**
Use **Notch width offset** and **Notch height offset** in Settings to match the
physical camera housing, or disable **Follow the display under the pointer**.
