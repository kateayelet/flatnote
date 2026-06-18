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

    /// True once notes are being stored in (and synced through) iCloud.
    var iCloudAvailable = false

    /// The iCloud container identifier. Must match the app's iCloud capability.
    private let ubiquityContainerID = "iCloud.com.aftrveil.flatnote"

    /// When set (tests), storage is this fixed local directory and iCloud is skipped.
    private let injectedDirectory: URL?

    /// The directory notes are read from and written to. Starts local and is
    /// swapped to the iCloud Documents container once that resolves.
    private var storageURL: URL

    private var documentsURL: URL { storageURL }

    init() {
        injectedDirectory = nil
        storageURL = Self.localDocumentsURL()
        // iCloud lookup can block, so resolve storage off the main thread and
        // seed/load once the real location (iCloud or local) is settled.
        resolveStorageAndLoad()
    }

    init(directory: URL) {
        injectedDirectory = directory
        storageURL = directory
        loadNotes()
    }

    private static func localDocumentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Storage resolution (iCloud with local fallback)

    private func resolveStorageAndLoad() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var resolved = Self.localDocumentsURL()
            var iCloud = false

            if let container = FileManager.default.url(forUbiquityContainerIdentifier: self.ubiquityContainerID) {
                let iCloudDocs = container.appendingPathComponent("Documents", isDirectory: true)
                try? FileManager.default.createDirectory(at: iCloudDocs, withIntermediateDirectories: true)
                self.migrateLocalNotes(from: Self.localDocumentsURL(), to: iCloudDocs)
                resolved = iCloudDocs
                iCloud = true
            }

            DispatchQueue.main.async {
                self.storageURL = resolved
                self.iCloudAvailable = iCloud
                self.loadNotes()
                if self.notes.isEmpty {
                    self.createWelcomeNote()
                }
            }
        }
    }

    /// Moves any local-only notes into iCloud the first time iCloud appears,
    /// skipping names that already exist there.
    private func migrateLocalNotes(from localDocs: URL, to iCloudDocs: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: localDocs, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }

        for item in items where ["md", "markdown", "txt"].contains(item.pathExtension.lowercased()) {
            let dest = iCloudDocs.appendingPathComponent(item.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            try? FileManager.default.setUbiquitous(true, itemAt: item, destinationURL: dest)
        }
    }

    /// Maps an iCloud placeholder URL (".Note.md.icloud") back to its real name.
    private static func resolveICloudPlaceholder(_ url: URL) -> URL {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return url }
        let real = String(name.dropFirst().dropLast(".icloud".count))
        return url.deletingLastPathComponent().appendingPathComponent(real)
    }

    // MARK: - Coordinated file access (safe for iCloud and local)

    private func coordinatedRead(_ url: URL) -> String {
        var text = ""
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { resolved in
            text = (try? String(contentsOf: resolved, encoding: .utf8)) ?? ""
        }
        return text
    }

    private func coordinatedWrite(_ content: String, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { resolved in
            do { try content.write(to: resolved, atomically: true, encoding: .utf8) }
            catch { writeError = error }
        }
        if let writeError { throw writeError }
        if let coordError { throw coordError }
    }

    private func coordinatedDelete(_ url: URL) throws {
        var coordError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { resolved in
            do { try FileManager.default.removeItem(at: resolved) }
            catch { deleteError = error }
        }
        if let deleteError { throw deleteError }
        if let coordError { throw coordError }
    }

    // MARK: - Notes API

    func loadNotes() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else {
            notes = []
            return
        }
        notes = contents
            .compactMap { url -> NoteFile? in
                let resolved = Self.resolveICloudPlaceholder(url)
                guard ["md", "markdown", "txt"].contains(resolved.pathExtension.lowercased()) else { return nil }
                if resolved != url {
                    // Not-yet-downloaded iCloud item: pull it for the next load.
                    try? FileManager.default.startDownloadingUbiquitousItem(at: resolved)
                }
                let attrs = try? FileManager.default.attributesOfItem(atPath: resolved.path)
                let modified = attrs?[.modificationDate] as? Date ?? Date()
                return NoteFile(id: resolved, name: resolved.lastPathComponent, modifiedDate: modified)
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }

    func createNote(name: String) -> NoteFile? {
        let url = documentsURL.appendingPathComponent(name)
        do {
            try coordinatedWrite("", to: url)
        } catch {
            lastError = "Could not create \"\(name)\". \(error.localizedDescription)"
            return nil
        }
        let note = NoteFile(id: url, name: name, modifiedDate: Date())
        notes.insert(note, at: 0)
        return note
    }

    func readContent(of note: NoteFile) -> String {
        coordinatedRead(note.url)
    }

    func saveContent(_ content: String, to note: NoteFile) {
        do {
            try coordinatedWrite(content, to: note.url)
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
            try coordinatedDelete(note.url)
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
            try coordinatedWrite(content, to: dest)
            loadNotes()
        } catch {
            lastError = "Could not import \"\(url.lastPathComponent)\". \(error.localizedDescription)"
        }
    }

    // MARK: - Markdown export

    private func exportTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FlatNoteExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A URL that exports this note as markdown. Notes already stored as .md
    /// export their own file; .txt or other notes get a .md copy of their
    /// content so everything leaves the app as markdown.
    func markdownExportURL(for note: NoteFile) -> URL {
        guard note.url.pathExtension.lowercased() != "md" else { return note.url }
        let dest = exportTempDir().appendingPathComponent(note.displayName + ".md")
        try? readContent(of: note).write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    /// Markdown export URLs for every note. All notes are written as deduped
    /// .md files in a temp folder so the batch is uniform and collision-free.
    func markdownExportURLs() -> [URL] {
        let dir = exportTempDir()
        var used = Set<String>()
        return notes.map { note in
            var name = note.displayName + ".md"
            var counter = 2
            while used.contains(name.lowercased()) {
                name = "\(note.displayName) \(counter).md"
                counter += 1
            }
            used.insert(name.lowercased())
            let dest = dir.appendingPathComponent(name)
            try? readContent(of: note).write(to: dest, atomically: true, encoding: .utf8)
            return dest
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
        try? coordinatedWrite(content, to: url)
        loadNotes()
    }
}
