import SwiftUI

struct NotesPanel: View {
    @ObservedObject var notes = NoteStore.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    notes.appendDateLine()
                    focused = true
                } label: { label("clock", "Timestamp") }
                Button { notes.copyAll() } label: { label("doc.on.doc", "Copy") }
                Button { notes.saveToFile() } label: { label("square.and.arrow.down", "Save") }
                Button { notes.clear() } label: { label("trash", "Clear") }
                Spacer()
                Text("\(RunMode.isRendering ? Self.demoNote.count : notes.scratchpad.count) chars")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                if RunMode.isRendering {
                    Text(Self.demoNote)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundColor(Theme.text)
                        .lineSpacing(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                } else {
                    if notes.scratchpad.isEmpty {
                        Text("Quick note — it autosaves locally.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notes.scratchpad)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundColor(Theme.text)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .focused($focused)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }

    /// Offscreen renders show a neutral note instead of the user's scratchpad.
    private static let demoNote = """
    Release checklist
    • Record the notch strip moving
    • Screenshot every panel
    • Write the README and docs
    • Tag v1.0.0

    Idea: a breathing ring while a focus timer runs.
    """

    private func label(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(title).font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Theme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}
