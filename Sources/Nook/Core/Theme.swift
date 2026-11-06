import SwiftUI

enum Theme {
    static let shell = Color.black
    static let shellSoft = Color.white.opacity(0.06)
    static let text = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.40)
    static let hairline = Color.white.opacity(0.10)
    static let chip = Color.white.opacity(0.08)

    static var accent: Color { Util.color(hex: AppSettings.shared.accentHex) }

    static func panelHeight(for tab: NookTab) -> CGFloat {
        tab.preferredHeight
    }
}

struct PressableButtonStyle: ButtonStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : (tint == nil ? 0.08 : 0.0)))
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ChipLabel: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = Theme.textSecondary
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.chip))
    }
}
