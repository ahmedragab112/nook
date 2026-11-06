# Privacy

Nook is built to run on your Mac. There is no account, no analytics, no crash
reporting and no background network traffic.

## What stays on the Mac

- **Media** — playback metadata comes from the system MediaRemote framework and
  is held in memory.
- **Calendar and Reminders** — read through EventKit after you grant access.
  Events are never written or uploaded.
- **Camera** — the Mirror preview is rendered straight from an
  `AVCaptureSession`; frames are not saved.
- **Screen** — the colour picker samples the screen through ScreenCaptureKit
  and keeps only the pixels it displays.
- **Clipboard** — history is kept in memory (up to the limit you set) and is
  discarded when Nook quits.
- **System stats** — CPU, memory, disk, battery and network counters are read
  locally through IOKit and `host_statistics`.
- **Notes, Shortcuts, Shelf** — stored in
  `~/Library/Application Support/Nook/` on your disk.

## The one network request

Weather uses the public [Open-Meteo](https://open-meteo.com) API:

- `geocoding-api.open-meteo.com/v1/search` resolves the city you type, once per
  city, and caches the coordinates in memory.
- `api.open-meteo.com/v1/forecast` fetches current conditions and a six-day
  outlook. Results are cached for ten minutes and persisted so the panel can
  show the last forecast offline.

The requests contain coordinates and nothing else — no identifier, account or
device information. If you never open Weather, Nook makes no network calls of
its own.

## Agent chats

The Agents panel is a front-end for tools you install yourself:

- **Qoder** runs the local `qodercli` binary. Prompts and replies travel
  according to how that CLI is configured, which may include Qoder's cloud
  service.
- **OpenCode** talks to a server on `127.0.0.1:4096` (configurable).

Nook does not add logging, telemetry or a proxy to either path. Treat an agent
conversation with the same privacy expectations as using that tool directly.

## Permissions

Nook requests Calendar, Reminders, Camera and Screen Recording only when a panel
needs them. Declining leaves the rest of the app unchanged. macOS records these
grants against the app's signature; because local builds are ad-hoc signed,
rebuilding may require granting them again.

## Removing your data

Quit Nook and delete:

```bash
rm -rf ~/Library/Application\ Support/Nook
defaults delete com.ahmedragab.nook
rm -rf /Applications/Nook.app
```

That removes notes, shelf files, shortcuts, the weather cache and every
preference. Nothing is left elsewhere on the system.

## Contact

Found a privacy problem? Open an issue at
[github.com/ahmedragab112/nook/issues](https://github.com/ahmedragab112/nook/issues).
