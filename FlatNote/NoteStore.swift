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

    // Identity is the file URL. Two references to the same note are equal even
    // if their cached modification dates differ.
    static func == (lhs: NoteFile, rhs: NoteFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
class NoteStore {
    var notes: [NoteFile] = []

    /// Set when a file operation fails so the UI can surface it. Cleared by the view on dismiss.
    var lastError: String?

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

    func createNote(name: String) -> NoteFile? {
        let url = documentsURL.appendingPathComponent(name)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Could not create \"\(name)\". \(error.localizedDescription)"
            return nil
        }
        let note = NoteFile(id: url, name: name, modifiedDate: Date())
        notes.insert(note, at: 0)
        return note
    }

    func readContent(of note: NoteFile) -> String {
        (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
    }

    func saveContent(_ content: String, to note: NoteFile) {
        do {
            try content.write(to: note.url, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Could not save \"\(note.displayName)\". \(error.localizedDescription)"
        }
    }

    /// Renames a note's file on disk. Returns the updated note, or nil if the
    /// name is empty, collides with an existing note, or the move fails.
    func renameNote(_ note: NoteFile, to newName: String) -> NoteFile? {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let hasKnownExtension = ["md", "markdown", "txt"].contains { lower.hasSuffix("." + $0) }
        let finalName = hasKnownExtension ? trimmed : trimmed + ".md"
        let dest = documentsURL.appendingPathComponent(finalName)

        if dest == note.url { return note }
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            lastError = "A note named \"\((finalName as NSString).deletingPathExtension)\" already exists."
            return nil
        }

        do {
            try FileManager.default.moveItem(at: note.url, to: dest)
        } catch {
            lastError = "Could not rename \"\(note.displayName)\". \(error.localizedDescription)"
            return nil
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
        let modified = attrs?[.modificationDate] as? Date ?? note.modifiedDate
        let renamed = NoteFile(id: dest, name: finalName, modifiedDate: modified)
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = renamed
        }
        return renamed
    }

    func deleteNote(_ note: NoteFile) {
        do {
            try FileManager.default.removeItem(at: note.url)
            notes.removeAll { $0.id == note.id }
        } catch {
            lastError = "Could not delete \"\(note.displayName)\". \(error.localizedDescription)"
        }
    }

    func preview(for note: NoteFile) -> String {
        let content = readContent(of: note).trimmingCharacters(in: .whitespacesAndNewlines)
        if content.count <= 120 { return content }
        return String(content.prefix(120)) + "..."
    }

    func importFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Could not access \"\(url.lastPathComponent)\"."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let dest = uniqueDestination(for: url.lastPathComponent)
            try content.write(to: dest, atomically: true, encoding: .utf8)
            loadNotes()
        } catch {
            lastError = "Could not import \"\(url.lastPathComponent)\". \(error.localizedDescription)"
        }
    }

    /// Returns a destination URL that does not collide with an existing note,
    /// appending " 2", " 3", ... before the extension as needed.
    func uniqueDestination(for filename: String) -> URL {
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var candidate = documentsURL.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = documentsURL.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
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
