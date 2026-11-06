import SwiftUI

struct LauncherPanel: View {
    @ObservedObject var store = LauncherStore.shared

    private let columns = [GridItem(.adaptive(minimum: 58, maximum: 66), spacing: 8)]

    var body: some View {
        VStack(spacing: 6) {
            SectionHeader(title: "Shortcuts", subtitle: "Tap to launch · right-click for options")
                .overlay(alignment: .trailing) {
                    Button {
                        store.pick()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(PressableButtonStyle())
                }

            if store.items.isEmpty {
                EmptyState(symbol: "square.grid.2x2",
                           title: "No shortcuts yet",
                           detail: "Add the apps and folders you live in.",
                           actionTitle: "Add items") {
                    store.pick()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.items) { item in tile(item) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func tile(_ item: LaunchItem) -> some View {
        Button {
            if item.isFolder { store.openFolder(item) } else { store.launch(item) }
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                Text(item.name)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.03)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { store.launch(item) }
            Button("Reveal in Finder") { Util.reveal(item.url) }
            Divider()
            Button("Move left") { store.move(item, to: -1) }
            Button("Move right") { store.move(item, to: 1) }
            Button("Remove", role: .destructive) { store.remove(item) }
        }
        .help(item.url.path)
    }
}
