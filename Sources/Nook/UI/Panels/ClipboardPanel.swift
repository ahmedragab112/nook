import SwiftUI

struct ClipboardPanel: View {
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var settings = AppSettings.shared
    @State private var query = ""

    private var filtered: [ClipItem] {
        guard !query.isEmpty else { return store.items }
        return store.items.filter { $0.preview.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Button {
                    store.clear()
                } label: {
                    Text("Clear")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))

            if !settings.clipboardEnabled {
                EmptyState(symbol: "doc.on.clipboard",
                           title: "History is off",
                           detail: "Enable clipboard history in Settings.",
                           actionTitle: "Enable") { settings.clipboardEnabled = true }
            } else if filtered.isEmpty {
                EmptyState(symbol: "doc.on.clipboard",
                           title: "Nothing copied yet",
                           detail: "Copy anything and it lands here (last \(settings.clipboardLimit)).")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { item in row(item) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ item: ClipItem) -> some View {
        Button {
            store.copy(item, thenPaste: settings.pasteOnSelect)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol(for: item))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.preview)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy") { store.copy(item) }
            if item.kind == .files {
                Button("Reveal") { Util.reveal(item.fileURLs[0]) }
            }
            Divider()
            Button("Forget", role: .destructive) { store.remove(item) }
        }
    }

    private func symbol(for item: ClipItem) -> String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc"
        }
    }
}
