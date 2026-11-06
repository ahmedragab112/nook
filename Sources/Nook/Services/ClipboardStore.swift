import AppKit
import Combine
import Foundation

struct ClipItem: Identifiable, Equatable {
    enum Kind { case text, image, files }
    let id = UUID()
    var kind: Kind
    var text: String
    var preview: String
    var date: Date
    var fileURLs: [URL]
    var imageData: Data?

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool { lhs.id == rhs.id }
}

/// Rolling clipboard history (text, images, files) with one-click restore.
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published var items: [ClipItem] = []

    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.tick() }
    }

    func tick() {
        guard AppSettings.shared.clipboardEnabled else { return }
        let board = NSPasteboard.general
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        capture(from: board)
    }

    func capture(droppedText: String) {
        append(ClipItem(kind: .text, text: droppedText, preview: droppedText,
                        date: Date(), fileURLs: [], imageData: nil))
    }

    private func capture(from board: NSPasteboard) {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let names = urls.map { $0.lastPathComponent }
            append(ClipItem(kind: .files, text: names.joined(separator: ", "),
                            preview: names.joined(separator: ", "),
                            date: Date(), fileURLs: urls, imageData: nil))
            return
        }
        if let tiff = board.data(forType: .tiff) ?? board.data(forType: .png),
           NSImage(data: tiff) != nil {
            append(ClipItem(kind: .image, text: "Image \(Util.bytes(Int64(tiff.count)))",
                            preview: "Image \(Util.bytes(Int64(tiff.count)))",
                            date: Date(), fileURLs: [], imageData: tiff))
            return
        }
        if let string = board.string(forType: .string), !string.isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = items.first, last.kind == .text, last.text == trimmed { return }
            append(ClipItem(kind: .text, text: string, preview: folded(trimmed),
                            date: Date(), fileURLs: [], imageData: nil))
        }
    }

    private func folded(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " · ")
        return oneLine.count > 120 ? String(oneLine.prefix(120)) + "…" : oneLine
    }

    private func append(_ item: ClipItem) {
        items.removeAll { $0 == item }
        items.insert(item, at: 0)
        let limit = AppSettings.shared.clipboardLimit
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    func copy(_ item: ClipItem, thenPaste: Bool = false) {
        let board = NSPasteboard.general
        board.clearContents()
        switch item.kind {
        case .text:
            board.setString(item.text, forType: .string)
        case .image:
            if let data = item.imageData { board.setData(data, forType: .tiff) }
        case .files:
            board.writeObjects(item.fileURLs as [NSURL])
        }
        changeCount = board.changeCount
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if thenPaste && AppSettings.shared.pasteOnSelect { pasteNow() }
        ToastCenter.shared.show(item.kind == .text ? "Copied" : "Restored to clipboard")
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    private func pasteNow() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
