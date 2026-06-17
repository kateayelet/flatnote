import Foundation
import Observation

struct NoteFile: Identifiable, Hashable {
    let id: URL
    var name: String
    var modifiedDate: Date

    var url: URL { id }

    var displayName: String {
        (name as NSString).deletingPathExtension
    }
}

@Observable
class NoteStore {
    var notes: [NoteFile] = []

    private let _directory: URL?

    private var documentsURL: URL {
        _directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        _directory = nil
        loadNotes()
        if notes.isEmpty {
            createWelcomeNote()
        }
    }

    init(directory: URL) {
        _directory = directory
        loadNotes()
    }

    func loadNotes() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            notes = contents
                .filter { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }
                .compactMap { url -> NoteFile? in
                    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let modified = attrs?[.modificationDate] as? Date ?? Date()
                    return NoteFile(id: url, name: url.lastPathComponent, modifiedDate: modified)
                }
                .sorted { $0.modifiedDate > $1.modifiedDate }
        } catch {
            notes = []
        }
    }

    func createNote(name: String) -> NoteFile {
        let url = documentsURL.appendingPathComponent(name)
        try? "".write(to: url, atomically: true, encoding: .utf8)
        let note = NoteFile(id: url, name: name, modifiedDate: Date())
        notes.insert(note, at: 0)
        return note
    }

    func readContent(of note: NoteFile) -> String {
        (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
    }

    func saveContent(_ content: String, to note: NoteFile) {
        try? content.write(to: note.url, atomically: true, encoding: .utf8)
    }

    func deleteNote(_ note: NoteFile) {
        try? FileManager.default.removeItem(at: note.url)
        notes.removeAll { $0.id == note.id }
    }

    func preview(for note: NoteFile) -> String {
        let content = readContent(of: note).trimmingCharacters(in: .whitespacesAndNewlines)
        if content.count <= 120 { return content }
        return String(content.prefix(120)) + "..."
    }

    func importFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let dest = documentsURL.appendingPathComponent(url.lastPathComponent)
        try? content.write(to: dest, atomically: true, encoding: .utf8)
        loadNotes()
    }

    private func createWelcomeNote() {
        let content = """
        # Welcome to FlatNote

        FlatNote is a plain markdown editor. Everything you write here is saved as a **.md** file.

        ## Why Markdown?

        Markdown files are plain text. They will never corrupt, never require a specific app to open, and never become unreadable. No proprietary formats. No lock-in. Your words belong to you.

        ## Quick Reference

        *italic* -- single asterisks
        **bold** -- double asterisks
        ~~strikethrough~~ -- double tildes
        `inline code` -- backticks

        # Heading 1
        ## Heading 2
        ### Heading 3

        - Bullet item
        1. Numbered item
        - [ ] Task
        - [x] Done

        > Blockquote

        ---

        Tap **+** to create a new note.
        """
        let url = documentsURL.appendingPathComponent("Welcome to FlatNote.md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        loadNotes()
    }
}
