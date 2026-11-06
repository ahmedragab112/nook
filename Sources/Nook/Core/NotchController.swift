import AppKit
import Combine
import SwiftUI

final class NotchController {
    static private(set) var shared: NotchController!

    let state: NotchState
    private let settings: AppSettings
    private var panel: NotchPanel?
    private var hosting: NotchHostingView<AnyView>?
    private var info: ScreenInfo
    private var collapseWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?
    private var suppressHoverUntil = Date.distantPast
    private var activities: [NotchState.LiveActivity.Kind: NotchState.LiveActivity] = [:]
    private var globalClickMonitor: Any?
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var localClickMonitor: Any?
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var keyMonitor: Any?
    private var pollTimer: Timer?
    private var lastSignature = ""

    init(settings: AppSettings) {
        self.settings = settings
        self.state = NotchState(settings: settings)
        if let screen = ScreenGeometry.bestScreen() {
            self.info = ScreenGeometry.info(for: screen)
        } else {
            self.info = ScreenInfo.fallback()
        }
        NotchController.shared = self
    }

    // MARK: - lifecycle

    func start() {
        let panel = NotchPanel(contentRect: NSRect(origin: .zero, size: compactSize))
        let root = AnyView(NotchRootView().environmentObject(state).environmentObject(settings))
        let hosting = NotchHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting

        position(animated: false)
        panel.orderFrontRegardless()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleGlobalClick()
        }
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.evaluateHover()
        }
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.evaluateHover()
            return event
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.focusPanel()
            return event
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
        // Scroll events can land on the app under the notch; a global
        // monitor catches those without extra permissions.
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // escape
                self.unpin()
                self.collapse()
                return nil
            }
            if self.state.expanded, self.state.isHovering || self.state.pinned {
                if event.keyCode == 123 { self.stepTab(-1); return nil }
                if event.keyCode == 124 { self.stepTab(1); return nil }
            }
            return event
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshEnvironment()
        }
        refreshEnvironment()
    }

    // MARK: - geometry

    var compactSize: CGSize {
        let w = max(130, info.notchWidth + settings.notchWidthOffset)
        var h = info.notchHeight + settings.notchHeightOffset
        if !info.hasNotch { h = max(32, h) }
        return CGSize(width: w, height: max(26, h))
    }

    /// The collapsed card grows out of the notch (or the menu bar on
    /// notch-less Macs) so it reads as the notch itself getting bigger.
    static let activityPillSize = CGSize(width: 600, height: 54)
    static let hudPillSize = CGSize(width: 600, height: 64)
    /// Compact now-playing strip: artwork, title and live wave bars.
    static let miniMediaPillSize = CGSize(width: 340, height: 36)

    /// Width of the camera housing the card has to keep clear of.
    var compactNotchGap: CGFloat { info.hasNotch ? info.notchWidth : 0 }
    var compactNotchHeight: CGFloat { max(0, info.notchHeight) }

    /// Timer/calendar/agent activities stay visible. Media shows a small
    /// strip while playing, and the full control card on hover.
    private func cardVisible(_ activity: NotchState.LiveActivity?) -> Bool {
        guard let activity else { return false }
        guard activity.kind == .media else { return true }
        return state.showsMediaCard || NowPlayingService.shared.isPlaying
    }

    var collapsedSize: CGSize {
        guard !state.expanded else { return compactSize }
        if state.hud != nil { return Self.hudPillSize }
        if let activity = state.liveActivity {
            if activity.kind == .media {
                if state.showsMediaCard { return Self.activityPillSize }
                if NowPlayingService.shared.isPlaying { return Self.miniMediaPillSize }
            } else if cardVisible(activity) {
                return Self.activityPillSize
            }
        }
        return compactSize
    }

    var expandedSize: CGSize {
        let base = settings.expandedSize
        return CGSize(width: base.width, height: base.height + state.visibleTab.preferredHeight)
    }

    private var currentSize: CGSize { state.expanded ? expandedSize : collapsedSize }

    private var targetOrigin: NSPoint {
        let size = currentSize
        let frame = info.frame
        let x = frame.midX - size.width / 2
        return NSPoint(x: x, y: frame.maxY - size.height)
    }

    func applyFrame(animated: Bool) {
        guard let panel else { return }
        let size = currentSize
        let rect = NSRect(origin: targetOrigin, size: size)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animated ? 0.34 : 0
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.98, 0.24, 1.0)
                panel.animator().setFrame(rect, display: true)
            }
        } else {
            panel.setFrame(rect, display: true)
        }
    }

    private func position(animated: Bool) {
        applyFrame(animated: animated)
    }

    // MARK: - state changes

    func hover(_ inside: Bool) {
        state.isHovering = inside
        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            guard settings.hoverToOpen, Date() >= suppressHoverUntil, !state.isHidden else { return }
            // HUDs are transient, so hovering must not swap them for the
            // full panel. The media strip is its own control surface:
            // hovering grows it to the full card without opening the panel.
            guard state.hud == nil else { return }
            if state.liveActivity?.kind == .media {
                mediaPeekWork?.cancel()
                mediaPeekWork = nil
                if !state.showsMediaCard, !state.expanded {
                    state.showsMediaCard = true
                    applyFrame(animated: true)
                }
                return
            }
            expand(pinned: state.pinned)
        } else {
            if state.showsMediaCard, !state.expanded {
                scheduleMediaCardHide()
            }
            guard settings.autoCollapse else { return }
            if state.pinned { return }
            scheduleCollapse()
        }
    }

    func expand(pinned: Bool? = nil) {
        guard !state.expanded else {
            if let pinned { state.pinned = pinned; applyFrame(animated: false) }
            return
        }
        state.visibleTab = state.tab
        hideMediaCard(animated: false)
        withAnimationCurve { self.state.phase = .expanded }
        if let pinned { state.pinned = pinned }
        applyFrame(animated: true)
    }

    func collapse() {
        guard state.expanded else { return }
        suppressHoverUntil = Date().addingTimeInterval(0.35)
        hideMediaCard(animated: false)
        withAnimationCurve { self.state.phase = .collapsed }
        applyFrame(animated: true)
    }

    func open(tab: NookTab, pin: Bool = true) {
        state.tab = tab
        state.visibleTab = tab
        state.pinned = pin
        remember(tab)
        hideMediaCard(animated: false)
        if !state.expanded {
            withAnimationCurve { self.state.phase = .expanded }
            applyFrame(animated: true)
        } else {
            applyFrame(animated: true)
        }
    }

    func unpin() {
        state.pinned = false
    }

    func toggle() {
        if state.expanded {
            unpin()
            collapse()
        } else {
            expand(pinned: true)
        }
    }

    /// Brings the accessory app forward and makes the panel key so controls
    /// draw active and can take keyboard focus (notes, search, sliders).
    func activate() {
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func focusPanel() {
        guard let panel, panel.frame.contains(NSEvent.mouseLocation) else { return }
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        if !panel.isKeyWindow { panel.makeKey() }
        // Any click means the user is working in the panel; keep it open
        // even if the pointer wanders off while typing or dragging.
        if state.expanded { state.pinned = true }
    }

    func stepTab(_ delta: Int) {
        let tabs = state.visibleTabs
        guard !tabs.isEmpty else { return }
        let idx = tabs.firstIndex(of: state.visibleTab) ?? 0
        let next = tabs[(idx + delta + tabs.count) % tabs.count]
        state.visibleTab = next
        state.tab = next
        remember(next)
        applyFrame(animated: true)
    }

    private func remember(_ tab: NookTab) {
        guard settings.rememberLastTab else { return }
        settings.lastTab = tab.rawValue
    }

    private func withAnimationCurve(_ block: () -> Void) {
        NSAnimationContext.beginGrouping()
        block()
        NSAnimationContext.endGrouping()
    }

    func scheduleCollapseNow() {
        guard !state.pinned else { return }
        collapse()
    }

    private func evaluateHover() {
        guard let panel, !state.isHidden else { return }
        let point = NSEvent.mouseLocation
        let inside = panel.frame.contains(point)
        if inside != state.isHovering {
            hover(inside)
        }
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.pinned, !self.state.isHovering else { return }
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.15, settings.collapseDelay), execute: work)
    }

    private func handleGlobalClick() {
        guard state.expanded, state.pinned, let panel else { return }
        let mouse = NSEvent.mouseLocation
        if !panel.frame.contains(mouse) {
            unpin()
            collapse()
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard settings.scrollToOpen, !state.expanded, !state.isHidden, state.hud == nil else { return }
        guard let panel, panel.frame.contains(NSEvent.mouseLocation) else { return }
        guard abs(event.scrollingDeltaY) > 0 || abs(event.scrollingDeltaX) > 0 else { return }
        expand(pinned: true)
    }

    // MARK: - HUD & live activity

    func show(hud: HUDMessage, duration: TimeInterval = 1.5, respectSystemHUD: Bool = true) {
        if respectSystemHUD, !settings.showSystemHUD { return }
        state.hud = hud
        hudWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.hud = nil
            self.syncCompactFrame()
        }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        syncCompactFrame()
    }

    /// Resizes the collapsed card when a HUD or live activity appears.
    private func syncCompactFrame() {
        guard !state.expanded, panel != nil else { return }
        applyFrame(animated: true)
    }

    // MARK: - media strip

    private var mediaPeekWork: DispatchWorkItem?

    private func scheduleMediaCardHide() {
        mediaPeekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isHovering else { return }
            self.hideMediaCard(animated: true)
        }
        mediaPeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func hideMediaCard(animated: Bool) {
        mediaPeekWork?.cancel()
        mediaPeekWork = nil
        guard state.showsMediaCard else { return }
        state.showsMediaCard = false
        if animated, !state.expanded {
            applyFrame(animated: true)
        }
    }

    func setActivity(_ activity: NotchState.LiveActivity?) {
        if let activity {
            activities[activity.kind] = activity
        }
        refreshActivity()
    }

    func clearActivity(_ kind: NotchState.LiveActivity.Kind) {
        activities.removeValue(forKey: kind)
        refreshActivity()
    }

    private func refreshActivity() {
        let mode = settings.compactContent
        let picked: NotchState.LiveActivity?
        switch mode {
        case .none: picked = nil
        case .media: picked = activities[.media]
        case .timer: picked = activities[.timer]
        case .calendar: picked = activities[.calendar]
        case .auto:
            picked = activities[.bluetooth] ?? activities[.agent] ?? activities[.timer] ?? activities[.media] ?? activities[.calendar]
        }

        if picked?.kind != .media {
            hideMediaCard(animated: false)
        }

        if state.liveActivity != picked {
            state.liveActivity = picked
        }

        // The strip grows and shrinks as playback starts, stops, or another
        // activity takes priority; only resize when the target actually differs.
        guard !state.expanded else { return }
        let target = collapsedSize
        if let panel,
           abs(panel.frame.width - target.width) > 0.5 || abs(panel.frame.height - target.height) > 0.5 {
            applyFrame(animated: true)
        }
    }

    // MARK: - drops

    func handleDrop(urls: [URL], text: String?) {
        if !urls.isEmpty {
            ShelfStore.shared.add(urls)
            open(tab: .shelf, pin: true)
            ToastCenter.shared.show("\(urls.count) item\(urls.count == 1 ? "" : "s") added to shelf")
            return
        }
        if let text, !text.isEmpty {
            ClipboardStore.shared.capture(droppedText: text)
            open(tab: .clipboard, pin: true)
            ToastCenter.shared.show("Text captured")
        }
    }

    // MARK: - environment polling

    private func refreshEnvironment() {
        guard let screen = ScreenGeometry.bestScreen() else { return }
        let next = ScreenGeometry.info(for: screen)
        let signature = "\(next.frame)|\(next.hasNotch)|\(Int(next.notchWidth))|\(Int(next.notchHeight))"
        let shouldHide = next.menuBarHidden && settings.hideInFullscreen
        if shouldHide != state.isHidden {
            state.isHidden = shouldHide
            if shouldHide { panel?.orderOut(nil) } else { panel?.orderFrontRegardless() }
        }
        if !state.expanded {
            let changed = next.frame != info.frame
            info = next
            if changed || signature != lastSignature {
                lastSignature = signature
                applyFrame(animated: false)
            }
        } else {
            info = next
        }
    }

    /// Developer helper: renders the current window content to a PNG for visual checks.
    func snapshotPNG(to path: String) {
        guard let view = panel?.contentView, view.bounds.width > 1 else { return }
        let scale: CGFloat = 2
        let width = Int(view.bounds.width * scale)
        let height = Int(view.bounds.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: width,
                                         pixelsHigh: height,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return }
        rep.size = view.bounds.size

        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            // NSGraphicsContext(bitmapImageRep:) already maps points to the
            // rep's pixel size; only flip y so the flipped hosting view lands
            // upright in the bitmap.
            ctx.cgContext.translateBy(x: 0, y: view.bounds.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            view.layer?.render(in: ctx.cgContext)
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    func rebuildForSettings() {
        if let screen = ScreenGeometry.bestScreen() { info = ScreenGeometry.info(for: screen) }
        applyFrame(animated: false)
        refreshActivity()
    }
}
