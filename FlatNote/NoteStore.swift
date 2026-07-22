import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

/// How the library orders its notes. Persisted, so the choice survives launches.
enum NoteSortOrder: String, CaseIterable, Identifiable {
    case modified, created, title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .modified: return "Last Edited"
        case .created: return "Date Created"
        case .title: return "Title"
        }
    }
}

struct NoteFile: Identifiable, Hashable {
    let id: URL
    var name: String
    var modifiedDate: Date
    var createdDate: Date = .distantPast
    /// The top-level library folder holding this note, nil for the root.
    /// Folders are real directories on disk — never a hidden database.
    var folder: String? = nil

    /// Stable identity within the library, used for pin state.
    var relativePath: String {
        folder.map { "\($0)/\(name)" } ?? name
    }

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

    /// Top-level subdirectories of the library, sorted. Each is a real folder
    /// on disk; the filter chips in the library map straight onto these.
    var folders: [String] = []

    /// Set when a file operation fails so the UI can surface it. Cleared by the view on dismiss.
    var lastError: String?

    /// True once notes are being stored in (and synced through) iCloud.
    var iCloudAvailable = false

    /// True once the storage location (iCloud or local) has resolved. Files
    /// handed to the app before this must wait, or they land in the wrong
    /// storage and become invisible to the library.
    var isReady = false

    private static let sortOrderKey = "librarySortOrder"
    private static let pinnedNamesKey = "pinnedNoteNames"

    /// Library sort order. Setting it re-sorts and persists.
    var sortOrder: NoteSortOrder = NoteSortOrder(
        rawValue: UserDefaults.standard.string(forKey: NoteStore.sortOrderKey) ?? ""
    ) ?? .modified {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
            sortNotes()
        }
    }

    /// Pinned notes sort to the top. Keyed by filename (not full URL) so pins
    /// survive the local-to-iCloud storage migration; kept out of the .md files
    /// themselves — pin state is app state, the note stays plain Markdown.
    private(set) var pinnedNames: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: NoteStore.pinnedNamesKey) ?? []
    )

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
        isReady = true
    }

    private static func localDocumentsURL() -> URL {
        let fm = FileManager.default
        #if os(macOS)
        // On the Mac, .documentDirectory is the user's real ~/Documents. Keep
        // notes in a visible FlatNote subfolder rather than scattering them there.
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlatNote", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
        #else
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
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
                // Seed the welcome note only on the very first launch. After
                // that the user's choice to delete it is respected; they can
                // restore it deliberately from Settings.
                if !self.hasSeededWelcome {
                    if self.notes.isEmpty {
                        self.createWelcomeNote()
                    }
                    self.hasSeededWelcome = true
                }
                self.isReady = true
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

    /// Moves a file with presenter notification, so an NSDocument that has the
    /// file open follows the rename (window title, future autosaves) instead of
    /// resurrecting the old name on its next save.
    private func coordinatedMove(from src: URL, to dst: URL) throws {
        var coordError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: src, options: .forMoving,
                               writingItemAt: dst, options: [],
                               error: &coordError) { newSrc, newDst in
            do {
                coordinator.item(at: newSrc, willMoveTo: newDst)
                try FileManager.default.moveItem(at: newSrc, to: newDst)
                coordinator.item(at: newSrc, didMoveTo: newDst)
            } catch { moveError = error }
        }
        if let moveError { throw moveError }
        if let coordError { throw coordError }
    }

    /// Deleting a note must be recoverable — the files are the user's. Trash,
    /// never destroy. `trashItem` puts the note in the visible Trash (Finder's
    /// on Mac, the Files app's Recently Deleted on iOS); iCloud items land in
    /// the container's `.Trash`. Only if the volume has no trash at all (rare:
    /// some network/USB volumes) do we fall back to a real delete.
    private func coordinatedDelete(_ url: URL) throws {
        var coordError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { resolved in
            do {
                do {
                    try FileManager.default.trashItem(at: resolved, resultingItemURL: nil)
                } catch CocoaError.featureUnsupported {
                    try FileManager.default.removeItem(at: resolved)
                }
            }
            catch { deleteError = error }
        }
        if let deleteError { throw deleteError }
        if let coordError { throw coordError }
    }

    // MARK: - Notes API

    func loadNotes() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            notes = []
            folders = []
            return
        }

        var found: [NoteFile] = []
        var dirs: [String] = []
        for url in contents {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let name = url.lastPathComponent
                // "assets" is where pasted images land (LIFE-116), not a
                // notes folder — a root note's images must not become a chip.
                guard name != ".Trash", name != "assets" else { continue }
                dirs.append(name)
                // Notes anywhere inside the folder belong to it; deeper
                // nesting still shows up rather than silently vanishing.
                if let sub = fm.enumerator(at: url, includingPropertiesForKeys:
                    [.contentModificationDateKey, .creationDateKey],
                    options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in sub {
                        if let note = Self.noteFile(at: fileURL, folder: name) {
                            found.append(note)
                        }
                    }
                }
            } else if let note = Self.noteFile(at: url, folder: nil) {
                found.append(note)
            }
        }
        folders = dirs.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        notes = found
        sortNotes()
    }

    /// Builds a NoteFile from a URL if it is a markdown-family file,
    /// resolving iCloud placeholders along the way.
    private static func noteFile(at url: URL, folder: String?) -> NoteFile? {
        let resolved = resolveICloudPlaceholder(url)
        guard ["md", "markdown", "txt"].contains(resolved.pathExtension.lowercased()) else { return nil }
        if resolved != url {
            // Not-yet-downloaded iCloud item: pull it for the next load.
            try? FileManager.default.startDownloadingUbiquitousItem(at: resolved)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        let modified = attrs?[.modificationDate] as? Date ?? Date()
        let created = attrs?[.creationDate] as? Date ?? modified
        return NoteFile(id: resolved, name: resolved.lastPathComponent,
                        modifiedDate: modified, createdDate: created, folder: folder)
    }

    // MARK: - Folders

    /// Creates a real directory in the library. Returns the cleaned folder
    /// name, or nil if the name is unusable or the directory cannot be made.
    @discardableResult
    func createFolder(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
        guard !trimmed.isEmpty, trimmed != ".Trash" else { return nil }
        let url = storageURL.appendingPathComponent(trimmed, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } catch {
                lastError = "Could not create the folder \"\(trimmed)\"."
                return nil
            }
        }
        loadNotes()
        return trimmed
    }

    /// Moves a note into a library folder (nil = the root). The .md file
    /// really moves on disk.
    @discardableResult
    func moveNote(_ note: NoteFile, toFolder folder: String?) -> NoteFile? {
        guard folder != note.folder else { return note }
        let dir = folder.map { storageURL.appendingPathComponent($0, isDirectory: true) } ?? storageURL
        let dest = uniqueDestination(for: note.name, in: dir)
        do {
            try coordinatedMove(from: note.url, to: dest)
        } catch {
            lastError = "Could not move \"\(note.displayName)\". \(error.localizedDescription)"
            return nil
        }
        let oldPath = note.relativePath
        let moved = NoteFile(id: dest, name: dest.lastPathComponent,
                             modifiedDate: note.modifiedDate, createdDate: note.createdDate,
                             folder: folder)
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = moved
        }
        pinFollowsRename(from: oldPath, to: moved.relativePath)
        sortNotes()
        return moved
    }

    // MARK: - Sorting & pins

    private func sortNotes() {
        notes = Self.sorted(notes, by: sortOrder, pinned: pinnedNames)
    }

    static func sorted(_ notes: [NoteFile], by order: NoteSortOrder, pinned: Set<String>) -> [NoteFile] {
        notes.sorted { a, b in
            let aPinned = pinned.contains(a.relativePath), bPinned = pinned.contains(b.relativePath)
            if aPinned != bPinned { return aPinned }
            switch order {
            case .modified: return a.modifiedDate > b.modifiedDate
            case .created: return a.createdDate > b.createdDate
            case .title: return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            }
        }
    }

    func isPinned(_ note: NoteFile) -> Bool {
        pinnedNames.contains(note.relativePath)
    }

    func togglePin(_ note: NoteFile) {
        if pinnedNames.contains(note.relativePath) {
            pinnedNames.remove(note.relativePath)
        } else {
            pinnedNames.insert(note.relativePath)
        }
        persistPins()
        sortNotes()
    }

    private func persistPins() {
        UserDefaults.standard.set(Array(pinnedNames).sorted(), forKey: Self.pinnedNamesKey)
    }

    /// Pins are keyed by filename, so a rename must carry the pin along.
    private func pinFollowsRename(from oldName: String, to newName: String) {
        guard pinnedNames.remove(oldName) != nil else { return }
        pinnedNames.insert(newName)
        persistPins()
    }

    /// Creates an empty, uniquely-named note to open immediately. Its real
    /// title is derived from the first line when the editor closes. Created
    /// inside `folder` when the library is filtered to one.
    func createBlankNote(in folder: String? = nil) -> NoteFile? {
        let dir = folder.map { storageURL.appendingPathComponent($0, isDirectory: true) } ?? documentsURL
        let name = uniqueDestination(for: "New Note.md", in: dir).lastPathComponent
        return createNote(name: name, folder: folder)
    }

    /// Derives a filename-safe title from the first non-empty line of content.
    static func titleFromContent(_ content: String) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .lazy
            .map { strippedMarkdown(String($0)).trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
        var title = firstLine
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        if title.count > 50 {
            title = String(title.prefix(50)).trimmingCharacters(in: .whitespaces)
        }
        return title
    }

    /// Renames a note to match its first line, deduplicating collisions. No-op
    /// when the first line is empty or already matches the current name.
    @discardableResult
    func renameToFirstLine(_ note: NoteFile, content: String) -> NoteFile {
        let title = Self.titleFromContent(content)
        guard !title.isEmpty, title != note.displayName else { return note }
        let ext = note.url.pathExtension.isEmpty ? "md" : note.url.pathExtension
        let dest = uniqueDestination(for: "\(title).\(ext)",
                                     in: note.url.deletingLastPathComponent())
        do {
            try coordinatedMove(from: note.url, to: dest)
        } catch {
            return note
        }
        let renamed = NoteFile(id: dest, name: dest.lastPathComponent,
                               modifiedDate: Date(), createdDate: note.createdDate,
                               folder: note.folder)
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = renamed
        }
        pinFollowsRename(from: note.relativePath, to: renamed.relativePath)
        return renamed
    }

    func createNote(name: String, folder: String? = nil) -> NoteFile? {
        let dir = folder.map { storageURL.appendingPathComponent($0, isDirectory: true) } ?? documentsURL
        let url = dir.appendingPathComponent(name)
        do {
            try coordinatedWrite("", to: url)
        } catch {
            lastError = "Could not create \"\(name)\". \(error.localizedDescription)"
            return nil
        }
        let note = NoteFile(id: url, name: name, modifiedDate: Date(), createdDate: Date(), folder: folder)
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
        // Rename in place: a note in a folder stays in its folder.
        let dest = note.url.deletingLastPathComponent().appendingPathComponent(finalName)

        if dest == note.url { return note }
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            lastError = "A note named \"\((finalName as NSString).deletingPathExtension)\" already exists."
            return nil
        }

        do {
            try coordinatedMove(from: note.url, to: dest)
        } catch {
            lastError = "Could not rename \"\(note.displayName)\". \(error.localizedDescription)"
            return nil
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
        let modified = attrs?[.modificationDate] as? Date ?? note.modifiedDate
        let renamed = NoteFile(id: dest, name: finalName,
                               modifiedDate: modified, createdDate: note.createdDate,
                               folder: note.folder)
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = renamed
        }
        pinFollowsRename(from: note.relativePath, to: renamed.relativePath)
        return renamed
    }

    func deleteNote(_ note: NoteFile) {
        #if os(macOS)
        // If the note is open in a document window, close it first: an open
        // NSDocument is a file presenter, so deleting under it would block
        // the coordinator and let the next autosave resurrect the file.
        NSDocumentController.shared.document(for: note.url)?.close()
        #endif
        do {
            try coordinatedDelete(note.url)
            notes.removeAll { $0.id == note.id }
            if pinnedNames.remove(note.relativePath) != nil { persistPins() }
        } catch {
            lastError = "Could not delete \"\(note.displayName)\". \(error.localizedDescription)"
        }
    }

    /// The card preview: up to `limit` meaningful lines of the note, skipping
    /// a leading heading (the card already shows the title). Lines keep their
    /// Markdown so the card can render them.
    func previewLines(for note: NoteFile, limit: Int = 6) -> [String] {
        var lines = readContent(of: note)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = lines.first, first.hasPrefix("#") {
            lines.removeFirst()
        }
        return Array(lines.prefix(limit))
    }

    /// The first image the note references that exists on disk, for the card
    /// thumbnail. Relative paths resolve against the note's own directory —
    /// the same way any other Markdown app would read the file.
    func thumbnailURL(for note: NoteFile) -> URL? {
        let content = readContent(of: note)
        guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)\s]+)\)"#) else { return nil }
        let range = NSRange(content.startIndex..., in: content)
        for match in regex.matches(in: content, range: range) {
            guard let pathRange = Range(match.range(at: 1), in: content) else { continue }
            let path = String(content[pathRange])
            guard !path.contains("://") else { continue }
            let url = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : note.url.deletingLastPathComponent().appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    func preview(for note: NoteFile) -> String {
        let content = Self.strippedMarkdown(readContent(of: note))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if content.count <= 120 { return content }
        return String(content.prefix(120)) + "..."
    }

    /// Removes markdown syntax so previews read as plain prose.
    static func strippedMarkdown(_ text: String) -> String {
        let leadingMarker = #"^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+\.\s+)"#
        let horizontalRule = #"^\s*([-*_]\s*){3,}$"#

        let lines = text.components(separatedBy: .newlines).map { line -> String in
            if line.range(of: horizontalRule, options: .regularExpression) != nil { return "" }
            return line.replacingOccurrences(of: leadingMarker, with: "", options: .regularExpression)
        }

        var joined = lines.joined(separator: " ")
        // Links: [text](url) -> text
        joined = joined.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // Inline emphasis / code markers
        for token in ["**", "__", "~~", "`", "*", "_"] {
            joined = joined.replacingOccurrences(of: token, with: "")
        }
        // Collapse runs of whitespace
        joined = joined.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return joined
    }

    /// Opens a file the system handed us (tapped in the Files app, AirDrop, a
    /// share sheet, etc). If the file already lives in our storage it is opened
    /// in place; anything else is imported as a copy first. Returns the note to
    /// open, or nil if it could not be read.
    func openIncomingFile(_ url: URL) -> NoteFile? {
        let resolved = Self.resolveICloudPlaceholder(url).standardizedFileURL
        guard ["md", "markdown", "txt"].contains(resolved.pathExtension.lowercased()) else {
            lastError = "\"\(resolved.lastPathComponent)\" is not a note FlatNote can open."
            return nil
        }

        // Already one of our notes (opened in place from the FlatNote folder)?
        if let existing = note(matching: resolved) { return existing }

        // Sitting in our storage but not yet loaded? Pick it up and retry.
        if resolved.deletingLastPathComponent().standardizedFileURL == documentsURL.standardizedFileURL {
            loadNotes()
            if let existing = note(matching: resolved) { return existing }
        }

        // From the system Inbox the OS already made a copy for us (share
        // sheet, Mail attachment); adopt that copy into the library.
        let inbox = Self.localDocumentsURL()
            .appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL
        if resolved.deletingLastPathComponent().standardizedFileURL == inbox {
            return importFile(from: url)
        }

        // Anything else we can reach directly opens IN PLACE — never a copy.
        // (The pre-1.1 behavior imported a copy here; that is the same design
        // that caused the Mac silent-save incident, and it is gone.)
        return openExternalFile(url)
    }

    // MARK: - External notes (opened in place)

    /// Files opened in place from outside our storage. We hold each one's
    /// security scope for the life of the process (scopes die with it), so
    /// the editor can keep reading and writing the file where it lives.
    private var externalScopedURLs: [URL] = []

    /// Recent externally opened files, newest first, resolved from bookmarks
    /// at launch. Bookmarks are app configuration, not note data.
    private(set) var externalRecents: [NoteFile] = []

    private static let externalRecentsKey = "externalRecentBookmarks"
    private static let maxExternalRecents = 8

    /// True when a note lives outside the library folder (opened in place).
    func isExternal(_ note: NoteFile) -> Bool {
        note.url.standardizedFileURL.deletingLastPathComponent() != documentsURL.standardizedFileURL
    }

    /// Open a file that lives outside our storage IN PLACE. The file is never
    /// copied: we retain its security scope for the session so edits write
    /// back to the file where it lives, and keep a bookmark so it appears in
    /// Recents next launch.
    func openExternalFile(_ url: URL) -> NoteFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        let resolved = Self.resolveICloudPlaceholder(url).standardizedFileURL

        guard ["md", "markdown", "txt"].contains(resolved.pathExtension.lowercased()) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            lastError = "\"\(resolved.lastPathComponent)\" is not a note FlatNote can open."
            return nil
        }
        guard FileManager.default.isReadableFile(atPath: resolved.path) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            lastError = "\"\(resolved.lastPathComponent)\" could not be opened."
            return nil
        }

        if scoped { externalScopedURLs.append(url) }

        let attrs = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        let modified = attrs?[.modificationDate] as? Date ?? Date()
        let note = NoteFile(id: resolved, name: resolved.lastPathComponent, modifiedDate: modified)
        recordExternalRecent(url, note: note)
        return note
    }

    /// Resolve persisted recent-file bookmarks (dropping any that no longer
    /// resolve), newest first. Scopes are not started here — only when a
    /// recent is actually opened.
    func loadExternalRecents() {
        let blobs = UserDefaults.standard.array(forKey: Self.externalRecentsKey) as? [Data] ?? []
        var items: [NoteFile] = []
        var kept: [Data] = []
        for data in blobs {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { continue }
            var blob = data
            if stale, let fresh = try? url.bookmarkData() { blob = fresh }
            kept.append(blob)
            items.append(NoteFile(id: url.standardizedFileURL, name: url.lastPathComponent, modifiedDate: .distantPast))
        }
        externalRecents = items
        if kept.count != blobs.count { UserDefaults.standard.set(kept, forKey: Self.externalRecentsKey) }
    }

    /// Open a file from the Recents list: re-resolve its bookmark so we get a
    /// fresh security scope, then the normal in-place path.
    func openExternalRecent(_ note: NoteFile) -> NoteFile? {
        let blobs = UserDefaults.standard.array(forKey: Self.externalRecentsKey) as? [Data] ?? []
        for data in blobs {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
                  url.standardizedFileURL == note.url else { continue }
            return openExternalFile(url)
        }
        lastError = "\"\(note.displayName)\" is no longer where it was. Open it again from the Files app."
        return nil
    }

    func removeExternalRecent(_ note: NoteFile) {
        let blobs = UserDefaults.standard.array(forKey: Self.externalRecentsKey) as? [Data] ?? []
        let kept = blobs.filter { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return false }
            return url.standardizedFileURL != note.url
        }
        UserDefaults.standard.set(kept, forKey: Self.externalRecentsKey)
        externalRecents.removeAll { $0.id == note.id }
    }

    /// Record (or bump) a just-opened external file. The bookmark must be
    /// made while the security scope is active.
    private func recordExternalRecent(_ url: URL, note: NoteFile) {
        guard let bookmark = try? url.bookmarkData() else { return }
        var blobs = UserDefaults.standard.array(forKey: Self.externalRecentsKey) as? [Data] ?? []
        // De-dup by resolved URL, newest first.
        blobs.removeAll { data in
            var stale = false
            guard let existing = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return true }
            return existing.standardizedFileURL == note.url
        }
        blobs.insert(bookmark, at: 0)
        if blobs.count > Self.maxExternalRecents { blobs = Array(blobs.prefix(Self.maxExternalRecents)) }
        UserDefaults.standard.set(blobs, forKey: Self.externalRecentsKey)
        externalRecents.removeAll { $0.id == note.id }
        externalRecents.insert(note, at: 0)
        if externalRecents.count > Self.maxExternalRecents {
            externalRecents = Array(externalRecents.prefix(Self.maxExternalRecents))
        }
    }

    private func note(matching url: URL) -> NoteFile? {
        notes.first { $0.url.standardizedFileURL == url }
    }

    /// Opens a companion note another app (FlatFile) requested by absolute path,
    /// e.g. via `flatnote://open?path=...`. When a note of that name already
    /// lives in our storage — the paired-folder workflow, where the `.md` sits in
    /// the FlatNote folder next to its `.csv` — we open that note IN PLACE so
    /// edits round-trip to the same file. Otherwise we fall back to the normal
    /// incoming-file handling (open-in-place if it is ours, else import a copy).
    func openPairedFile(path: String) -> NoteFile? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let name = url.lastPathComponent
        loadNotes()
        if let existing = notes.first(where: { $0.url.lastPathComponent == name }) {
            return existing
        }
        return openIncomingFile(url)
    }

    /// When the system opens an external file it first drops a copy in our
    /// Documents/Inbox. Once we have imported that copy, delete the original so
    /// stale Inbox files do not pile up.
    private func removeInboxLeftover(_ url: URL) {
        let inbox = Self.localDocumentsURL()
            .appendingPathComponent("Inbox", isDirectory: true)
            .standardizedFileURL
        guard url.standardizedFileURL.deletingLastPathComponent() == inbox else { return }
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func importFile(from url: URL) -> NoteFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let content = try coordinatedReadThrowing(url)
            let dest = uniqueDestination(for: url.lastPathComponent)
            try coordinatedWrite(content, to: dest)
            removeInboxLeftover(url)
            let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
            let modified = attrs?[.modificationDate] as? Date ?? Date()
            let note = NoteFile(id: dest, name: dest.lastPathComponent, modifiedDate: modified)
            notes.insert(note, at: 0)
            return note
        } catch {
            lastError = "Could not open \"\(url.lastPathComponent)\". \(error.localizedDescription)"
            return nil
        }
    }

    /// Coordinated read that surfaces failures, for importing external files.
    private func coordinatedReadThrowing(_ url: URL) throws -> String {
        var text = ""
        var readError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { resolved in
            do { text = try String(contentsOf: resolved, encoding: .utf8) }
            catch { readError = error }
        }
        if let readError { throw readError }
        if let coordError { throw coordError }
        return text
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

    /// Relative image paths a note references ("assets/x/img.png"), deduped.
    /// Remote and absolute references are left alone: only files that live
    /// with the note travel with it.
    private static func referencedImagePaths(in content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)\s]+)\)"#) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        var seen = Set<String>()
        var paths: [String] = []
        for match in regex.matches(in: content, range: range) {
            guard let r = Range(match.range(at: 1), in: content) else { continue }
            let path = String(content[r])
            guard !path.contains("://"), !path.hasPrefix("/"), !path.contains(".."),
                  seen.insert(path).inserted else { continue }
            paths.append(path)
        }
        return paths
    }

    /// What a note's export should be: the plain .md when it stands alone, or
    /// a zip of the note plus its images when it references any, so pictures
    /// survive the trip.
    func exportItemURL(for note: NoteFile) -> URL {
        let content = readContent(of: note)
        let base = note.url.deletingLastPathComponent()
        let fm = FileManager.default
        let refs = Self.referencedImagePaths(in: content).filter {
            fm.fileExists(atPath: base.appendingPathComponent($0).path)
        }
        guard !refs.isEmpty else { return markdownExportURL(for: note) }

        let stage = exportTempDir().appendingPathComponent(note.displayName, isDirectory: true)
        try? fm.removeItem(at: stage)
        try? fm.createDirectory(at: stage, withIntermediateDirectories: true)
        try? content.write(to: stage.appendingPathComponent(note.displayName + ".md"),
                           atomically: true, encoding: .utf8)
        for rel in refs {
            let dest = stage.appendingPathComponent(rel)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: base.appendingPathComponent(rel), to: dest)
        }
        return Self.zipped(stage) ?? stage
    }

    /// One zip of the whole library: every note as a .md file, folders
    /// preserved, referenced images included. Ordinary files all the way down.
    func libraryExportZipURL() -> URL? {
        guard !notes.isEmpty else { return nil }
        let fm = FileManager.default
        let stage = exportTempDir().appendingPathComponent("FlatNote Library", isDirectory: true)
        try? fm.removeItem(at: stage)
        try? fm.createDirectory(at: stage, withIntermediateDirectories: true)
        var used = Set<String>()
        for note in notes {
            let dir = note.folder.map { stage.appendingPathComponent($0, isDirectory: true) } ?? stage
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var name = note.displayName + ".md"
            var counter = 2
            while used.contains("\(note.folder ?? "")/\(name.lowercased())") {
                name = "\(note.displayName) \(counter).md"
                counter += 1
            }
            used.insert("\(note.folder ?? "")/\(name.lowercased())")
            let content = readContent(of: note)
            try? content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            let base = note.url.deletingLastPathComponent()
            for rel in Self.referencedImagePaths(in: content) {
                let src = base.appendingPathComponent(rel)
                let dest = dir.appendingPathComponent(rel)
                guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dest.path) else { continue }
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: src, to: dest)
            }
        }
        return Self.zipped(stage)
    }

    /// Folder to zip via the file coordinator's uploading reader, the same
    /// mechanism Files uses when a folder is shared. No archive library needed.
    private static func zipped(_ directory: URL) -> URL? {
        var result: URL?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading,
                                       error: &coordError) { zip in
            let dest = directory.deletingLastPathComponent()
                .appendingPathComponent(directory.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: zip, to: dest)) != nil { result = dest }
        }
        return result
    }

    /// Returns a destination URL that does not collide with an existing note,
    /// appending " 2", " 3", ... before the extension as needed.
    func uniqueDestination(for filename: String) -> URL {
        uniqueDestination(for: filename, in: documentsURL)
    }

    func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    /// The single source for the welcome note's contents, used both for the
    /// first-launch seed and for the "Restore Welcome Note" action so the two
    /// can never drift. Structure per the approved 1.1 mock: thesis intro,
    /// core principles, a live Get Started checklist.
    static let welcomeMarkdown = """
    # Welcome to FlatNote

    Markdown notes. No account.

    There is no account because there is nothing an account would do for you. Your notes are plain text files in your iCloud or in a folder on this device. Save them, export them, open them anywhere. They are yours.

    ## Core principles

    - Every note is a plain .md file, readable in any editor, on any device, today or in twenty years.
    - No account. Nothing to sign up for, nothing to lapse, nothing between you and your writing.
    - Nothing is sent to us. No ads, no tracking, no analytics. Your notes stay in the folder you choose, including iCloud if you use it.
    - Delete is honest. Deleted notes go to Trash, where they can still be recovered.

    ## Get started

    - [ ] Check this box. Tap it, and FlatNote writes the change to a real .md file.
    - [ ] Write a note. The pencil button starts one; the first line becomes its title.
    - [ ] Type `**stars**` around a word to make it bold. Formatting appears as you type.
    - [ ] Open the note called Markdown in one minute to see everything else.
    - [ ] Delete this note when you are done with it. It is an ordinary file, like every note here.

    Deleted it and want it back? Settings can restore it anytime.
    """

    /// The seeded sample note: the whole syntax, shown rather than described.
    static let sampleMarkdown = """
    # Markdown in one minute

    FlatNote formats your writing as you type. Type the plain markdown on the left, and it becomes the styled text on the right.

    ## Italic and bold

    `*italic*` becomes *italic*

    `**bold**` becomes **bold**

    `***bold italic***` becomes ***bold italic***

    `~~strikethrough~~` becomes ~~strikethrough~~

    Wrap a word in backticks for `inline code`.

    ## Headings

    Start a line with `#` for a heading. Add more hashes for smaller ones:

    ### Like this third-level heading

    ## Lists

    Start a line with `-` for a bullet:

    - A bullet
    - Another bullet

    ## Checklists

    Add `[ ]` after the dash for a checkbox. Tap or click the box to toggle it:

    - [ ] Something to do
    - [x] Something done

    ## Links

    `[words](https://example.com)` becomes [words](https://example.com)

    ## Quotes

    Start a line with `>` for a quote:

    > Like this

    ## Why markdown

    Your notes are plain text. Every one is a .md file you can open in any editor, on any device, today or in twenty years.

    That is the point. Some formats lock your words inside a single program. Miss an update, switch devices, or let a subscription lapse, and your own writing can become hard to reach. Plain text never does. It belongs to you, not to an app.

    FlatNote just makes plain text pleasant to write. The freedom was always yours.
    """

    /// Persisted so the welcome note is seeded only once, ever. After that,
    /// deleting it stays deleted unless the user restores it on purpose.
    private static let didSeedWelcomeKey = "FlatNoteDidSeedWelcome"
    private var hasSeededWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: Self.didSeedWelcomeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.didSeedWelcomeKey) }
    }

    private func createWelcomeNote() {
        // The sample rides along on the same first-launch seed. Both are
        // ordinary deletable files; deleting them is the first lesson that
        // the user owns the files. Sample first, welcome second: the library
        // sorts by modified date, and Welcome belongs on top.
        let sampleURL = documentsURL.appendingPathComponent("Markdown in one minute.md")
        try? coordinatedWrite(Self.sampleMarkdown, to: sampleURL)
        // Both writes land within the same second, which makes the
        // modified-date order unstable; backdate the sample so Welcome
        // reliably sorts on top.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)],
            ofItemAtPath: sampleURL.path
        )
        let url = documentsURL.appendingPathComponent("Welcome to FlatNote.md")
        try? coordinatedWrite(Self.welcomeMarkdown, to: url)
        loadNotes()
    }

    /// Recreates the welcome note on demand. If one already exists, its name is
    /// uniqued so the user's edited copy is never overwritten. Returns the new
    /// note so the caller can open it.
    @discardableResult
    func restoreWelcomeNote() -> NoteFile? {
        let url = uniqueDestination(for: "Welcome to FlatNote.md")
        do {
            try coordinatedWrite(Self.welcomeMarkdown, to: url)
        } catch {
            lastError = "Could not restore the welcome note."
            return nil
        }
        hasSeededWelcome = true
        loadNotes()
        return notes.first(where: { $0.url == url })
    }
}
