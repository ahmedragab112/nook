import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var settings: AppSettings
    @StateObject private var toast = ToastCenter.shared

    private var collapsedWidth: CGFloat { NotchController.shared.collapsedSize.width }
    private var expandedWidth: CGFloat { settings.expandedSize.width }

    /// The collapsed live card grows out of the notch / menu bar edge.
    /// Media counts as attached while it's playing (small strip) or hovered.
    private var isAttachedPill: Bool {
        guard !state.expanded else { return false }
        if state.hud != nil { return true }
        guard let activity = state.liveActivity else { return false }
        if activity.kind == .media {
            return state.showsMediaCard || NowPlayingService.shared.isPlaying
        }
        return true
    }

    /// The idle music strip sits flush against the screen edge like the built-in
    /// notch, so its top corners stay square instead of flaring inward.
    private var isMiniMediaStrip: Bool {
        guard !state.expanded, state.hud == nil else { return false }
        guard let activity = state.liveActivity, activity.kind == .media else { return false }
        return !state.showsMediaCard && NowPlayingService.shared.isPlaying
    }

    private var bottomRadius: CGFloat {
        state.expanded ? 26 : (isAttachedPill ? 22 : (state.isHovering ? 18 : 12))
    }

    private var flare: CGFloat {
        if state.expanded { return 12 }
        if isMiniMediaStrip { return 0 }
        return isAttachedPill ? 8 : 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            shell
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onHover { NotchController.shared.hover($0) }
        .onDrop(of: [.fileURL, .url, .plainText, .tiff, .png], isTargeted: nil) { providers in
            DropRouter.handle(providers)
        }
        .overlay(alignment: .bottom) {
            if let message = toast.message {
                Text(message)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast.message)
    }

    private var shell: some View {
        NotchShape(bottomRadius: bottomRadius,
                   flare: flare,
                   topRadius: 0)
            .fill(Color.black.opacity(settings.shellOpacity))
            .overlay(
                NotchShape(bottomRadius: bottomRadius,
                           flare: flare,
                           topRadius: 0)
                    .stroke(Color.white.opacity(state.expanded ? 0.10 : 0.05), lineWidth: 1)
            )
            .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.phase)
            .animation(.easeOut(duration: 0.2), value: state.isHovering)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if state.expanded {
                ExpandedView()
                    .frame(width: expandedWidth)
            } else {
                CompactView()
                    .frame(width: collapsedWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.phase)
    }
}

enum DropRouter {
    static func handle(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        var text: String?

        let group = DispatchGroup()
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    if let url = object { urls.append(url) }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                group.enter()
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    if let string = object as? String, text == nil { text = string }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            NotchController.shared.handleDrop(urls: urls, text: text)
        }
        return true
    }
}
