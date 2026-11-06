import SwiftUI

struct ColorPickerPanel: View {
    @ObservedObject var capture = ScreenCaptureService.shared
    @State private var point: CGPoint = .zero
    @State private var format: ScreenCaptureService.Format = .hex
    @State private var recent: [NSColor] = []
    @State private var sampled: NSColor?
    @State private var pixelPoint: CGPoint?

    private let displayWidth: CGFloat = 190
    private var displayHeight: CGFloat {
        guard capture.image != nil else { return 110 }
        let size = capture.pixelSize
        guard size.width > 0 else { return 110 }
        return displayWidth * (size.height / size.width)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                preview
                controls
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                readout
                recents
            }
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if capture.image == nil { capture.capture() }
            if point == .zero {
                point = CGPoint(x: displayWidth / 2, y: displayHeight / 2)
            }
            sample()
        }
    }

    @ViewBuilder private var preview: some View {
        if let image = capture.image {
            GeometryReader { geo in
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(alignment: .topLeading) { crosshair(in: geo.size) }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                point = CGPoint(x: max(0, min(geo.size.width, value.location.x)),
                                                y: max(0, min(geo.size.height, value.location.y)))
                                sample()
                            }
                    )
                    .onTapGesture { location in
                        point = location
                        sample()
                        commit()
                    }
            }
            .frame(width: displayWidth, height: displayHeight)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
        } else {
            EmptyState(symbol: "eyedropper",
                       title: capture.failed ? "Screen Recording is off" : "Capture the screen",
                       detail: capture.failed
                            ? "Allow Screen Recording for Nook in System Settings › Privacy & Security, then relaunch Nook."
                            : "Take a still frame, then hover to grab any pixel.",
                       actionTitle: capture.failed ? "Request access" : "Capture") {
                if capture.failed {
                    capture.requestAccess()
                } else {
                    capture.capture()
                }
            }
            .frame(width: displayWidth, height: 110)
        }
    }

    private func crosshair(in size: CGSize) -> some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 9, height: 0.5)
            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 0.5, height: 9)
        }
        .position(point)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                capture.capture()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 9, weight: .bold))
                    Text("Recapture").font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(PressableButtonStyle())
            .foregroundColor(Theme.textSecondary)

            Picker("", selection: $format) {
                ForEach(ScreenCaptureService.Format.allCases, id: \.self) { Text($0.label) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 130)
        }
    }

    private var readout: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(sampled ?? .black))
                    .frame(width: 38, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline))
                magnifier
            }
            Button {
                commit()
            } label: {
                Text(sampled == nil ? "Pick a pixel" : format.string(from: sampled!))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)
            .disabled(sampled == nil)
        }
    }

    private var magnifier: some View {
        Group {
            if let center = pixelPoint, let cg = capture.crop(center: center, side: 9) {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline))
            } else if capture.image != nil {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(Theme.textTertiary)
                    )
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textTertiary)
                    )
            }
        }
    }

    private var recents: some View {
        HStack(spacing: 4) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(color))
                    .frame(width: 14, height: 14)
                    .onTapGesture {
                        sampled = color
                        commit()
                    }
            }
        }
    }

    private func sample() {
        guard capture.image != nil else { return }
        let size = capture.pixelSize
        guard size.width > 0, size.height > 0 else { return }
        let pixel = CGPoint(x: point.x / displayWidth * size.width,
                            y: point.y / displayHeight * size.height)
        pixelPoint = pixel
        sampled = capture.color(at: pixel)
    }

    private func commit() {
        guard let color = sampled else { return }
        let text = format.string(from: color)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if !recent.contains(where: { Util.hexString($0) == Util.hexString(color) }) {
            recent.insert(color, at: 0)
            if recent.count > 6 { recent.removeLast() }
        }
        ToastCenter.shared.show("\(text) copied")
    }
}
