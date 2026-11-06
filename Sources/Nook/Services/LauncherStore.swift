import AppKit
import Combine
import Foundation

struct LaunchItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: URL
    var symbolFallback: String

    static func == (lhs: LaunchItem, rhs: LaunchItem) -> Bool { lhs.id == rhs.id }

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var isFolder: Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
}

/// Quick launch strip for apps, folders and files.
final class LauncherStore: ObservableObject {
    static let shared = LauncherStore()

    @Published var items: [LaunchItem] = []

    private let file: URL
    private let fm = FileManager.default

    private init() {
        file = Util.appSupport.appendingPathComponent("shortcuts.json")
        load()
        if items.isEmpty { seedDefaults() }
    }

    private func seedDefaults() {
        let guesses = ["System Settings", "Finder", "Safari", "Notes", "Calculator", "Terminal", "Activity Monitor"]
        var seeded: [LaunchItem] = []
        for name in guesses {
            for base in ["/System/Applications", "/System/Applications/Utilities", "/Applications"] {
                let url = URL(fileURLWithPath: base).appendingPathComponent(name + ".app")
                if fm.fileExists(atPath: url.path) {
                    seeded.append(LaunchItem(id: UUID(), name: name, url: url, symbolFallback: "app"))
                    break
                }
            }
        }
        items = seeded
        save()
    }

    func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canDownloadUbiquitousContents = true
        panel.resolvesAliases = true
        panel.prompt = "Add"
        panel.message = "Choose apps, folders or files to pin in the notch"
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls where !self.items.contains(where: { $0.url == url }) {
                self.items.append(LaunchItem(id: UUID(), name: url.deletingPathExtension().lastPathComponent,
                                             url: url, symbolFallback: "app"))
            }
            self.save()
        }
    }

    func remove(_ item: LaunchItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func move(_ item: LaunchItem, to offset: Int) {
        guard let from = items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = min(max(from + offset, 0), items.count - 1)
        items.swapAt(from, target)
        save()
    }

    func launch(_ item: LaunchItem) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: item.url, configuration: config)
    }

    func openFolder(_ item: LaunchItem) {
        NSWorkspace.shared.open(item.url)
    }

    private func save() {
        let dto = items.map { ["id": $0.id.uuidString, "name": $0.name, "path": $0.url.path] }
        if let data = try? JSONSerialization.data(withJSONObject: dto, options: [.prettyPrinted]) {
            try? data.write(to: file)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
        items = array.compactMap { dict in
            guard let idString = dict["id"], let id = UUID(uuidString: idString),
                  let name = dict["name"], let path = dict["path"],
                  fm.fileExists(atPath: path) else { return nil }
            return LaunchItem(id: id, name: name, url: URL(fileURLWithPath: path), symbolFallback: "app")
        }
    }
}
