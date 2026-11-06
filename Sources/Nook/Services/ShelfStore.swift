import AppKit
import Combine
import Foundation

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: URL
    var added: Date
    var size: Int64
    var isArchive: Bool

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }

    var kindLabel: String {
        if isArchive { return "Archive" }
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "File" : ext
    }

    var previewImage: NSImage? {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "webp", "bmp"]
        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// A drop zone that stages files so you can park them and drag them out later.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published var items: [ShelfItem] = []

    private let root: URL
    private let index: URL
    private let fm = FileManager.default

    private init() {
        root = Util.appSupport.appendingPathComponent("Shelf", isDirectory: true)
        index = root.appendingPathComponent("index.json")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        load()
        cleanAged()
    }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    func add(_ urls: [URL]) {
        for url in urls {
            let id = UUID()
            let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            do {
                if destinationStandardizing(url) != destination {
                    try fm.copyItem(at: url, to: destination)
                }
                let attrs = try? fm.attributesOfItem(atPath: destination.path)
                let size = (attrs?[.size] as? Int64) ?? 0
                let item = ShelfItem(id: id, name: url.lastPathComponent, url: destination,
                                     added: Date(), size: size,
                                     isArchive: ["zip", "tar", "gz", "tgz", "zipx", "bz2", "xz"].contains(url.pathExtension.lowercased()))
                items.insert(item, at: 0)
            } catch {
                NSLog("Nook shelf copy failed: \(error.localizedDescription)")
            }
        }
        save()
    }

    private func destinationStandardizing(_ url: URL) -> URL { url }

    func remove(_ item: ShelfItem) {
        let folder = root.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? fm.removeItem(at: folder)
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        for item in items {
            try? fm.removeItem(at: root.appendingPathComponent(item.id.uuidString, isDirectory: true))
        }
        items.removeAll()
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        Util.reveal(item.url)
    }

    func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }

    @discardableResult
    func extract(_ item: ShelfItem) -> URL? {
        let target = root.appendingPathComponent(item.id.uuidString + "_unzipped", isDirectory: true)
        try? fm.removeItem(at: target)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        let out = Util.shell("/usr/bin/ditto", ["-x", "-k", item.url.path, target.path])
        if out != nil || fm.fileExists(atPath: target.path) {
            NSWorkspace.shared.open(target)
            return target
        }
        return nil
    }

    private func save() {
        let dto = items.map { ["id": $0.id.uuidString, "name": $0.name, "path": $0.url.path,
                               "added": $0.added.timeIntervalSince1970, "size": $0.size, "archive": $0.isArchive] }
        if let data = try? JSONSerialization.data(withJSONObject: dto, options: [.prettyPrinted]) {
            try? data.write(to: index)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: index),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        items = array.compactMap { dict in
            guard let idString = dict["id"] as? String, let id = UUID(uuidString: idString),
                  let name = dict["name"] as? String, let path = dict["path"] as? String else { return nil }
            let url = URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: path) else { return nil }
            let attrs = try? fm.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? Int64) ?? Int64((dict["size"] as? Int) ?? 0)
            return ShelfItem(id: id, name: name, url: url,
                             added: Date(timeIntervalSince1970: dict["added"] as? Double ?? 0),
                             size: size, isArchive: dict["archive"] as? Bool ?? false)
            }.sorted { $0.added > $1.added }
    }

    private func cleanAged() {
        guard AppSettings.shared.shelfAutoClean else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        for item in items where item.added < cutoff { remove(item) }
    }
}
