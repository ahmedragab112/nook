import AVFoundation
import SwiftUI

struct MirrorPanel: View {
    @ObservedObject var camera = CameraService.shared
    @AppStorage("mirrorFlip") private var flipped = true

    var body: some View {
        VStack(spacing: 7) {
            if camera.authorized || RunMode.isRendering {
                preview
                controls
            } else {
                permissionView
            }
        }
        .onAppear {
            if !RunMode.isRendering { camera.start() }
        }
        .onDisappear { camera.stop() }
    }

    private var preview: some View {
        ZStack {
            if camera.running && camera.authorized {
                CameraPreview(session: camera.session)
                    .scaleEffect(x: flipped ? -1 : 1, y: 1)
            } else if RunMode.isRendering {
                demoPreview
            } else {
                Color.black
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .overlay(alignment: .topLeading) {
            if camera.running || RunMode.isRendering {
                HStack(spacing: 3) {
                    Circle()
                        .fill(camera.running ? Color.red : Theme.textTertiary)
                        .frame(width: 4, height: 4)
                    Text(camera.running ? "LIVE" : "PREVIEW")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(7)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                flipped.toggle()
            } label: {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(flipped ? Theme.accent : Theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .help("Flip the mirror")
            .padding(7)
        }
    }

    private var demoPreview: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.35), Color.black.opacity(0.9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "person.fill")
                .font(.system(size: 54, weight: .light))
                .foregroundColor(Color.white.opacity(0.14))
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                flipped.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(flipped ? "Mirror on" : "Mirror off")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(flipped ? Theme.accent.opacity(0.16) : Color.white.opacity(0.05)))
                .foregroundColor(flipped ? Theme.accent : Theme.textSecondary)
            }
            .buttonStyle(.plain)

            Text(camera.deviceName)
                .font(.system(size: 9))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)

            Spacer()

            Button {
                camera.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { camera.start() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(PressableButtonStyle())
            .foregroundColor(Theme.textTertiary)
            .help("Restart the camera")
        }
    }

    private var permissionView: some View {
        let blocked = camera.status == .denied || camera.status == .restricted
        return EmptyState(symbol: "camera",
                          title: blocked ? "Camera access is off" : "Look in the mirror",
                          detail: "Nook shows a live camera preview. Nothing is recorded or uploaded.",
                          actionTitle: blocked ? "Open System Settings" : "Allow camera") {
            if blocked {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
            } else {
                camera.requestAccess()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
