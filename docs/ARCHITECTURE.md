# Architecture

Nook is one window and a set of small services. Everything that draws is
SwiftUI; everything that talks to macOS is an `ObservableObject` service.

```
                    ┌───────────────────────────────┐
                    │           AppDelegate         │
                    │  accessory policy · hotkey    │
                    │  menu · render hooks          │
                    └───────────────┬───────────────┘
                                    │ owns
                    ┌───────────────▼───────────────┐
                    │         NotchController       │
                    │ window · geometry · gestures  │
                    │ expand / collapse · HUD       │
                    └───────┬───────────────┬───────┘
                            │               │
               ┌────────────▼───┐     ┌─────▼─────────────┐
               │   NotchState   │     │     NotchPanel    │
               │ phase · tab    │     │  NSPanel + hosting│
               │ activity · hud │     └─────┬─────────────┘
               └────────┬───────┘           │
                        │ published         │ hosts
               ┌────────▼───────────────────▼──────────┐
               │              NotchRootView            │
               │   NotchShape · size · transition      │
               │        ┌──────────────┐               │
               │        │ CompactView  │  collapsed    │
               │        └──────────────┘               │
               │        ┌──────────────┐               │
               │        │ ExpandedView │  expanded     │
               │        │  └ 14 panels │               │
               │        └──────────────┘               │
               └───────────────────────────────────────┘
```

## Window model

`NotchPanel` is a borderless `NSPanel`:

- `.nonactivatingPanel` so hovering never steals focus from the app you are in
- level `mainMenu + 6` so it floats above ordinary windows
- `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary` so it follows Spaces
  without appearing in Mission Control
- clear background, shadow, `sharingType = .readOnly`

`NotchHostingView` overrides `acceptsFirstMouse` so the first click reaches a
control even when another app is active — the behaviour of a menu bar popover.

A single panel is reused for every display. `NotchController.refreshEnvironment`
polls once a second, finds the screen under the pointer (when **Follow the display
under the pointer** is on), reads its notch geometry via `ScreenGeometry`, and
applies the new frame.

## Geometry

`ScreenGeometry.ScreenInfo` describes a display: frame, whether it has a notch,
the notch width and height, menu bar visibility and whether it is the built-in
panel.

On a MacBook Pro the panel opens around the camera housing. On a display without
a notch (including most external monitors) the same surface sits in the menu bar
with a minimum height of 32 pt. `Notch width offset` and `Notch height offset` in
Settings correct small mismatches.

Collapsed sizes live in `NotchController`:

| Mode | Size |
| --- | --- |
| Idle | notch width × notch height |
| Now-playing strip | 340 × 36 |
| Activity pill (timer, calendar, agent, Bluetooth) | 600 × 54 |
| HUD pill (volume, brightness) | 600 × 64 |
| Expanded | 460–820 × 220–320, depending on the size preset |

## Shape

`NotchShape` draws the silhouette as one path, with independent parameters:

- `topRadius` — the top edge. Idle and attached pills use `0`, keeping the strip
  flush with the screen edge, exactly like the hardware notch.
- `bottomRadius` — 12 pt idle, 22 pt on attached pills, 26 pt expanded.
- `flare` — how far the bottom corners bend outward to meet the camera housing.
  `0` gives a clean attached strip; `8` gives the concave "armpit" that makes the
  panel look grown out of the notch.

The same shape is used for the fill and the hairline stroke, so the outline never
drifts from the surface during the expand animation.

## State

`NotchState` is the only source of truth for presentation:

```swift
@Published var phase: Phase          // collapsed | expanded
@Published var tab: NookTab          // selected panel
@Published var visibleTab: NookTab   // rendered panel
@Published var pinned: Bool          // stays open after the pointer leaves
@Published var isHovering: Bool
@Published var hud: HUDMessage?
@Published var liveActivity: LiveActivity?
@Published var showsMediaCard: Bool  // full player instead of the strip
@Published var isHidden: Bool
```

`LiveActivity` is a small value type — kind (`media`, `timer`, `calendar`,
`agent`, `battery`, `bluetooth`), symbol, text, optional detail and optional
progress. Services push and clear activities through
`NotchController.setActivity(_:)` / `clearActivity(_:)`; the controller maps them
to a frame size and animates.

## Views

`NotchRootView` owns the silhouette and picks between `CompactView` and
`ExpandedView`. Its computed `isAttachedPill` and `isMiniMediaStrip` decide the
bottom radius and flare, so the shape reacts to playback without any extra
animation state.

`CompactView` renders one of four things:

1. a `HUDMessage` (volume, brightness)
2. an activity row (timer, calendar, agent, Bluetooth)
3. the mini media strip while audio plays
4. the full 600 × 54 media card when hovered or focused

Content is laid out in the two "ears" around the camera housing using
`compactNotchGap`, so text never hides behind the notch.

`ExpandedView` draws the tab bar plus the selected panel. Panels are plain
SwiftUI views; each one owns no window and no lifecycle beyond `onAppear` /
`onDisappear`.

## Services

| Service | Responsibility |
| --- | --- |
| `NowPlayingService` | Polls MediaRemote, exposes track, artwork and transport |
| `MediaRemoteAdapter` | Locates the bundled Perl adapter + framework and runs `get` / `stream` / `send` |
| `CalendarService` | EventKit events, next-event activity, demo data |
| `RemindersService` | EventKit reminder lists and completion |
| `WeatherService` | Open-Meteo geocoding + forecast, city setting |
| `TimerService` | Countdown/stopwatch, live strip progress |
| `BatteryReader` | IOKit battery percentage, charging HUD |
| `BluetoothService` | IOBluetooth connection events |
| `SystemDialService` | Volume and brightness sampling for the HUD |
| `StatsService` | CPU, memory, disk, battery, network, load, uptime |
| `ClipboardStore` | In-memory history of text, images and files |
| `ShelfStore` | Managed copies of dropped files, optional unzip |
| `LauncherStore` | User shortcuts to apps, folders and URLs |
| `NoteStore` | Single scratch note in Application Support |
| `CameraService` | AVCaptureSession for the mirror |
| `ScreenCaptureService` | ScreenCaptureKit frame + pixel sampling for the colour picker |
| `AgentService` | Qoder CLI process and OpenCode HTTP session |

`Util.appSupport` centralizes the Application Support path. `ToastCenter` shows
short confirmations inside the shell. `AppSettings` persists every preference in
`UserDefaults` and reloads the hotkey when its fields change.

## Media bridge

macOS has no public API for now-playing data, so Nook vendors
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause).
`Scripts/build_mediaremote.sh` compiles its Objective-C sources into
`MediaRemoteAdapter.framework`; `build_app.sh` copies the framework and the Perl
launcher into `Contents/Resources`.

At runtime `MediaRemoteAdapter` executes:

```
/usr/bin/perl <Resources>/mediaremote-adapter.pl <Resources>/MediaRemoteAdapter.framework get
```

and decodes the JSON into `Track`. Transport commands (`play`, `pause`, `next`,
`previous`, `seek`) go through the same adapter's `send` command. This is why
Music, Spotify and browser playback all work without per-app integrations.

## Rendering pipeline

`RunMode` (in `Core/Util.swift`) inspects `CommandLine.arguments`:

- `--demo` switches services to sample data
- any render/snapshot flag sets `isRendering`

`AppDelegate.renderPanels` opens each enabled tab in turn, waits for layout, calls
`controller.snapshotPNG(to:)`, and terminates. `snapshotPNG` renders the hosting
view's layer into an `NSBitmapImageRep` with a transparent background.

The documentation images in `docs/images` were composed from those captures with
CoreGraphics, using `--demo` so no personal event, note, file or clipboard data
appears.

## Threading and lifecycle

All UI and service state is main-thread. Timers and polling loops run on the main
run loop; network and EventKit callbacks hop back to the main queue before
publishing. `AppDelegate.applicationWillTerminate` shuts down the agent process
and stops services. Because the app is `LSUIElement`, quitting happens through
Settings → Quit or the app menu, not the Dock.
