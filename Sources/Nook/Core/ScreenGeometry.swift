import AppKit

struct ScreenInfo {
    var displayID: CGDirectDisplayID
    var frame: CGRect
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var menuBarHidden: Bool
    var isBuiltin: Bool
}

enum ScreenGeometry {
    /// Known built-in display notch sizes in points, keyed by native panel size.
    private static let known: [[Int]: (w: CGFloat, h: CGFloat)] = [
        [1470, 956]: (178, 32),   // MacBook Air 13 / MacBook Pro 13
        [1512, 982]: (184, 32),   // MacBook Pro 14
        [1728, 1117]: (209, 32),  // MacBook Pro 16
        [2560, 1664]: (184, 32),
        [3024, 1964]: (184, 32),
        [3456, 2234]: (209, 32),
        [3840, 2480]: (209, 32),
        [2880, 1864]: (209, 32)
    ]

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    private static func nativeSize(_ screen: NSScreen) -> [Int]? {
        guard let id = displayID(screen) else { return nil }
        guard let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] else { return nil }
        let best = modes.max { a, b in
            CGFloat(a.width) * CGFloat(a.height) < CGFloat(b.width) * CGFloat(b.height)
        } ?? CGDisplayCopyDisplayMode(id)
        guard let best else { return nil }
        return [best.width, best.height]
    }

    static func info(for screen: NSScreen) -> ScreenInfo {
        let frame = screen.frame
        let id = displayID(screen) ?? 0
        let visible = screen.visibleFrame
        let topInset = max(0, frame.maxY - visible.maxY)
        let menuBarHidden = topInset < 1
        let builtin = (displayID(screen).map { CGDisplayIsBuiltin($0) != 0 }) ?? false

        var width: CGFloat = 0
        var height: CGFloat = 0

        if #available(macOS 12.0, *) {
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let measured = right.minX - left.maxX
                if measured > 30 {
                    width = measured
                    height = max(topInset, 30)
                }
            }
        }

        if width == 0, builtin, let key = nativeSize(screen), let hit = known[key] {
            width = hit.w
            height = hit.h
        }

        guard width > 0 else {
            // External display: no physical notch, Nook draws a floating pill.
            return ScreenInfo(displayID: id, frame: frame, hasNotch: false,
                              notchWidth: 190, notchHeight: max(28, topInset),
                              menuBarHidden: menuBarHidden, isBuiltin: builtin)
        }
        return ScreenInfo(displayID: id, frame: frame, hasNotch: true,
                          notchWidth: width, notchHeight: max(30, height),
                          menuBarHidden: menuBarHidden, isBuiltin: builtin)
    }

    /// Screen the pointer lives on; falls back to main.
    static func activeScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(point) }) { return hit }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func bestScreen() -> NSScreen? {
        if AppSettings.shared.followFrontmostScreen { return activeScreen() }
        return NSScreen.main ?? NSScreen.screens.first
    }
}

extension ScreenInfo {
    static func fallback() -> ScreenInfo {
        ScreenInfo(displayID: 0, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                   hasNotch: false, notchWidth: 190, notchHeight: 32,
                   menuBarHidden: false, isBuiltin: false)
    }
}
