import AppKit
import Combine
import Foundation

final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published var scratchpad: String = "" {
        didSet { scheduleSave() }
    }

    private let file: URL
    private var saveWork: DispatchWorkItem?

    private init() {
        file = Util.appSupport.appendingPathComponent("scratch.txt")
        scratchpad = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            try? self.scratchpad.data(using: .utf8)?.write(to: self.file)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(scratchpad, forType: .string)
        ToastCenter.shared.show("Note copied")
    }

    func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "note.txt"
        panel.allowedContentTypes = []
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            try? self.scratchpad.write(to: url, atomically: true, encoding: .utf8)
            ToastCenter.shared.show("Saved to \(url.lastPathComponent)")
        }
    }

    func appendDateLine() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let prefix = scratchpad.isEmpty ? "" : "\n"
        scratchpad += "\(prefix)\(formatter.string(from: Date())) — "
    }

    func clear() {
        scratchpad = ""
    }
}
