# Contributing

Thanks for taking a look at Nook. It is a small, single-window app and the
fastest way to improve it is a focused pull request.

## Before you start

- Open an issue for anything larger than a bug fix or a small polish change.
  Panels, live activities and window behaviour are easy to discuss before code.
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) so changes land in the right
  layer: window and geometry in `NotchController`, presentation in
  `NotchRootView` / views, system access in services.

## Build

```bash
swift build
./Scripts/build_app.sh
open Nook.app
```

See [docs/BUILDING.md](docs/BUILDING.md) for requirements, permissions and
developer flags.

## Style

- Swift 5.10, no third-party packages.
- Keep UI on the main thread; hop back from network or framework callbacks.
- Prefer small `ObservableObject` services over global state.
- Match the existing naming and comment density: comments explain *why*, not
  *what*.
- Every new panel should work in the demo renderer. Add sample data to the
  existing `RunMode.isDemo` branches instead of reading real user data.

## Screenshots

Never commit a screenshot captured from a real session. Use the render pipeline:

```bash
.build/release/Nook --render=/tmp/nook-shots --demo
```

Then composite with the same background and padding as the images in
`docs/images`. Do not include calendar events, notes, clipboard contents, file
names or desktop windows from your machine.

## Pull requests

1. Keep the diff focused; unrelated refactors belong in their own PR.
2. Describe the behaviour change and what you tested (notch and non-notch
   display, light/dark wallpaper, multiple Spaces).
3. If you touch the window, include a before/after capture.
4. Update `README.md` or the docs when behaviour or flags change.

## License

By contributing you agree that your changes are released under the MIT license in
[LICENSE](LICENSE).
