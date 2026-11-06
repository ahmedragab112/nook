import SwiftUI
import UniformTypeIdentifiers

struct ShelfPanel: View {
    @ObservedObject var shelf = ShelfStore.shared
    @State private var targeted = false
    @EnvironmentObject var settings: AppSettings

    private let columns = [GridItem(.adaptive(minimum: 62, maximum: 74), spacing: 8)]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                SectionHeader(title: "File shelf", subtitle: "\(shelf.items.count) items · \(Util.bytes(shelf.totalSize))")
                Spacer()
                Menu {
                    Button("Open in Finder") { NSWorkspace.shared.open(Util.appSupport.appendingPathComponent("Shelf")) }
                    if !shelf.items.isEmpty {
                        Button("AirDrop all items") { airDrop(shelf.items.map(\.url)) }
                    }
                    Button("Auto-clean after 7 days", action: toggleClean)
                    Button("Clear shelf", role: .destructive) { shelf.clear() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)
            }

            if shelf.items.isEmpty {
                EmptyState(symbol: "tray.and.arrow.down",
                           title: "Drop files here",
                           detail: "Park anything in the notch, then drag it back out when you need it.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(shelf.items) { item in tile(item) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            DropRouter.handle(providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(targeted ? Theme.accent : Color.clear,
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .allowsHitTesting(false)
        )
    }

    private func toggleClean() { settings.shelfAutoClean.toggle() }

    private func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            ToastCenter.shared.show("AirDrop is unavailable")
            return
        }
        service.perform(withItems: urls)
    }

    private func tile(_ item: ShelfItem) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                if let preview = item.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Image(nsImage: Util.fileIcon(item.url))
                        .resizable()
                        .frame(width: 30, height: 30)
                }
            }
            .frame(height: 46)
            Text(item.name)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.white.opacity(0.03)))
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Reveal in Finder") { shelf.reveal(item) }
            Button("AirDrop…") { airDrop([item.url]) }
            Button("Copy path") { shelf.copyPath(item) }
            if item.isArchive {
                Button("Extract") { _ = shelf.extract(item) }
            }
            Divider()
            Button("Remove", role: .destructive) { shelf.remove(item) }
        }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help("\(item.name) · \(Util.bytes(item.size)) · added \(item.added.formatted(.relative(presentation: .named)))")
    }
}
