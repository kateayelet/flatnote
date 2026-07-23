import SwiftUI
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#else
import UIKit
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#endif

struct NoteLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = NoteStore()
    @State private var selectedNote: NoteFile?
    @State private var newNoteID: URL?
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingFilePicker = false
    @State private var renamingNote: NoteFile?
    @State private var renameText = ""
    /// nil = All notes; otherwise the name of the real directory being viewed.
    @State private var folderFilter: String?
    @State private var showingNewFolder = false
    @State private var newFolderText = ""
    /// Files handed to us before storage finished resolving; replayed once
    /// the store is ready so an at-launch open cannot race into the wrong
    /// storage location.
    @State private var pendingIncomingURLs: [URL] = []

    #if os(iOS)
    /// Types the Open File picker offers. Our exported markdown UTI plus
    /// plain text, so .md, .markdown, and .txt are all selectable.
    static let openableTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let md = UTType("net.daringfireball.markdown") { types.insert(md, at: 0) }
        return types
    }()

    /// Files opened in place from outside the library, most recent first.
    /// Tapping re-resolves the bookmark for a fresh security scope.
    @ViewBuilder
    private var externalRecentsSection: some View {
        if !store.externalRecents.isEmpty, searchText.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent Files")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(store.externalRecents) { item in
                    Button {
                        if let note = store.openExternalRecent(item) {
                            newNoteID = nil
                            selectedNote = note
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(item.displayName)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.removeExternalRecent(item)
                        } label: {
                            Label("Remove from Recents", systemImage: "minus.circle")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
    #endif

    /// Opens a note: a document window in place on macOS, a navigation push
    /// on iOS.
    private func open(_ note: NoteFile) {
        #if os(macOS)
        openAsDocument(note.url)
        #else
        selectedNote = note
        #endif
    }

    #if os(macOS)
    /// Routes through the shared document controller, the same path File >
    /// Open and Open Recent use, so the file is edited in place and lands in
    /// the recents list.
    private func openAsDocument(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            guard let error else { return }
            // An NSAlert rather than store.lastError: this can fire (e.g. a
            // flatnote:// handoff to an inaccessible path) while the library
            // window, which hosts the error alert, is closed.
            let alert = NSAlert()
            alert.messageText = "Could not open \"\(url.lastPathComponent)\""
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    #endif

    private func createAndOpenNote() {
        #if os(macOS)
        // A fresh untitled document: it only becomes a file when saved (the
        // panel defaults to the FlatNote iCloud folder), so closing an empty
        // note never litters the library.
        NSDocumentController.shared.newDocument(nil)
        #else
        // A note started while viewing a folder belongs to that folder.
        if let note = store.createBlankNote(in: folderFilter) {
            newNoteID = note.id
            selectedNote = note
        }
        #endif
    }

    private func beginRename(_ note: NoteFile) {
        renameText = note.displayName
        renamingNote = note
    }

    private func restoreWelcomeNote() {
        guard let note = store.restoreWelcomeNote() else { return }
        // Close Settings first, then open the restored note so the sheet
        // dismissal and the navigation push do not race.
        showingSettings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            newNoteID = nil
            open(note)
        }
    }

    /// Parses `flatnote://open?path=<abs path>` and opens the companion note.
    private func openPairedNote(from url: URL) -> NoteFile? {
        guard url.host == "open",
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "path" })?.value else {
            return nil
        }
        return store.openPairedFile(path: path)
    }

    /// Incoming URLs (flatnote:// pairing, or a file handed to us on iOS).
    /// Buffered until the store has resolved its storage location.
    private func handleIncoming(_ url: URL) {
        if url.scheme == "flatnote" {
            #if os(macOS)
            // Resolve the companion in our library by name and open it in
            // place as a document; fall back to the URL's own path.
            if url.host == "open",
               let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "path" })?.value {
                store.loadNotes()
                let target = URL(fileURLWithPath: path).standardizedFileURL
                let inStore = store.notes.first { $0.url.lastPathComponent == target.lastPathComponent }
                openAsDocument(inStore?.url ?? target)
            }
            #else
            if let note = openPairedNote(from: url) {
                newNoteID = nil
                selectedNote = note
            }
            #endif
            return
        }
        #if os(macOS)
        // Files are the document group's job; anything that still lands here
        // opens in place through the same machinery.
        openAsDocument(url)
        #else
        // A markdown file was tapped in Files, AirDrop, a share sheet, etc.
        // Open it (in place if it is already ours, otherwise as an imported
        // copy) instead of just launching to the library.
        if let note = store.openIncomingFile(url) {
            newNoteID = nil
            selectedNote = note
        }
        #endif
    }

    private var filteredNotes: [NoteFile] {
        var visible = store.notes
        if let folderFilter {
            visible = visible.filter { $0.folder == folderFilter }
        }
        if searchText.isEmpty { return visible }
        return visible.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            store.readContent(of: $0).localizedCaseInsensitiveContains(searchText)
        }
    }

    /// The filter chip row: All plus one chip per real directory, and the
    /// affordance to make a new one. Hidden while searching.
    @ViewBuilder
    private var folderChips: some View {
        if searchText.isEmpty, !store.folders.isEmpty || folderFilter != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    folderChip(label: "All", value: nil)
                    ForEach(store.folders, id: \.self) { folder in
                        folderChip(label: folder, value: folder)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    private func folderChip(label: String, value: String?) -> some View {
        let selected = folderFilter == value
        return Button {
            folderFilter = value
        } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                // Color.primary, not the hierarchical .primary style: the
                // foregroundStyle below would re-resolve the latter to the
                // background color and the selected pill would vanish.
                .background(selected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.quaternary.opacity(0.5)),
                            in: Capsule())
                .overlay {
                    if !selected {
                        Capsule().strokeBorder(.separator.opacity(0.7), lineWidth: 1)
                    }
                }
                .foregroundStyle(selected ? AnyShapeStyle(.background) : AnyShapeStyle(Color.primary))
        }
        .buttonStyle(.plain)
    }

    private func createFolderAndFilter() {
        guard let created = store.createFolder(newFolderText) else { return }
        newFolderText = ""
        folderFilter = created
    }

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if !store.isReady {
                    // Storage is still resolving (iCloud lookup runs off the
                    // main thread); claiming "No Notes" here flashes a false
                    // empty state on every cold launch (LIFE-159).
                    Color.clear
                } else if store.notes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } description: {
                        Text("Your thoughts deserve a quiet space.")
                    } actions: {
                        Button("New Note") { createAndOpenNote() }
                            .buttonStyle(.borderedProminent)
                            .tint(.primary)
                    }
                } else {
                    ScrollView {
                    #if os(iOS)
                    externalRecentsSection
                    #endif
                    folderChips
                    if filteredNotes.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView {
                                Label("Empty Folder", systemImage: "folder")
                            } description: {
                                Text("Notes you move or create here will appear.")
                            }
                            .padding(.top, 40)
                        } else {
                            ContentUnavailableView.search(text: searchText)
                                .padding(.top, 40)
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredNotes) { note in
                                NoteCardCell(
                                    note: note,
                                    previewLines: store.previewLines(for: note),
                                    thumbnail: store.thumbnailURL(for: note),
                                    isPinned: store.isPinned(note),
                                    folders: store.folders,
                                    showsFolder: folderFilter == nil,
                                    exportURL: { store.exportItemURL(for: note) },
                                    onOpen: { open(note) },
                                    onRename: { beginRename(note) },
                                    onTogglePin: { store.togglePin(note) },
                                    onMove: { store.moveNote(note, toFolder: $0) },
                                    onDelete: { store.deleteNote(note) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    }
                }
            }
            #if os(iOS)
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.large)
            #else
            // The Mac window belongs to the app, not a folder: title it FlatNote.
            .navigationTitle("FlatNote")
            #endif
            #if DEBUG
            .onAppear {
                // UI-inspection hook: launch with SIMCTL_CHILD_FLATNOTE_OPEN_FIRST=1
                // to jump straight into the first note for screenshots. Notes load
                // asynchronously, so retry briefly until one is available.
                if ProcessInfo.processInfo.environment["FLATNOTE_OPEN_FIRST"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if selectedNote == nil, let first = store.notes.first {
                            open(first)
                        }
                    }
                }
                if ProcessInfo.processInfo.environment["FLATNOTE_SHOW_ABOUT"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        showingAbout = true
                    }
                }
            }
            #endif
            #if os(iOS)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Notes"
            )
            #else
            .searchable(text: $searchText, prompt: "Search Notes")
            #endif
            .navigationDestination(item: $selectedNote) { note in
                EditorView(
                    store: store,
                    note: note,
                    isNew: note.id == newNoteID,
                    onRequestRename: { beginRename(note) }
                )
            }
            .onChange(of: scenePhase) { _, phase in
                // Pick up notes added or removed outside the app.
                if phase == .active { store.loadNotes() }
            }
            .onOpenURL { url in
                // At launch the store may still be resolving its storage
                // location (iCloud vs local). Handling a file before that
                // finishes would import into the wrong place, so buffer it.
                if store.isReady {
                    handleIncoming(url)
                } else {
                    pendingIncomingURLs.append(url)
                }
            }
            #if os(iOS)
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: Self.openableTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first, let note = store.openExternalFile(url) {
                        newNoteID = nil
                        selectedNote = note
                    }
                case .failure(let error):
                    store.lastError = error.localizedDescription
                }
            }
            .task { store.loadExternalRecents() }
            #endif
            .onChange(of: store.isReady) { _, ready in
                guard ready, !pendingIncomingURLs.isEmpty else { return }
                let urls = pendingIncomingURLs
                pendingIncomingURLs = []
                urls.forEach(handleIncoming)
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingFilePicker = true } label: {
                        Image(systemName: "folder")
                    }
                    .tint(.primary)
                    .accessibilityLabel("Open File")
                }
                #else
                ToolbarItem(placement: .navigation) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.primary)
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort Notes By", selection: Binding(
                            get: { store.sortOrder },
                            set: { store.sortOrder = $0 }
                        )) {
                            ForEach(NoteSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                        Divider()
                        Button {
                            showingNewFolder = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        // Decreasing stacked lines: the standard sort glyph.
                        // Up/down arrows read as a transfer/sync icon.
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .tint(.primary)
                    .accessibilityLabel("Sort and Organize")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { createAndOpenNote() } label: {
                        // The primary action: visibly weightier than Sort.
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                    }
                    .tint(.primary)
                }
            }
            .alert("New Folder", isPresented: $showingNewFolder) {
                TextField("name", text: $newFolderText)
                Button("Create") { createFolderAndFilter() }
                Button("Cancel", role: .cancel) { newFolderText = "" }
            } message: {
                Text("A real folder in your library. Notes you move into it move on disk.")
            }
            .alert("Rename Note", isPresented: Binding(
                get: { renamingNote != nil },
                set: { if !$0 { renamingNote = nil } }
            ), presenting: renamingNote) { note in
                TextField("filename", text: $renameText)
                Button("Rename") {
                    if let renamed = store.renameNote(note, to: renameText),
                       selectedNote?.id == note.id {
                        selectedNote = renamed
                    }
                    renamingNote = nil
                    renameText = ""
                }
                Button("Cancel", role: .cancel) {
                    renamingNote = nil
                    renameText = ""
                }
            } message: { _ in
                Text("Enter a new name for this note.")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    noteCount: store.notes.count,
                    exportZipURL: store.libraryExportZipURL(),
                    iCloudAvailable: store.iCloudAvailable,
                    onRestoreWelcome: restoreWelcomeNote
                )
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: .flatnoteShowAbout)) { _ in
                showingAbout = true
            }
            .onAppear {
                // Cold launch from the Home Screen quick action: the shortcut
                // arrived before any view was listening.
                if AppDelegate.pendingShortcutType == "com.aftrveil.flatnote.about" {
                    AppDelegate.pendingShortcutType = nil
                    showingAbout = true
                }
            }
            #endif
            .alert(
                "Something Went Wrong",
                isPresented: Binding(
                    get: { store.lastError != nil },
                    set: { if !$0 { store.lastError = nil } }
                ),
                presenting: store.lastError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }
}

// MARK: - About

/// The "Well, what is FlatNote?" card. Same copy everywhere it appears:
/// Settings row, Home Screen quick action, and the Mac About window.
/// Copy locked by Kate 2026-07-21.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "FlatNote \(version) (Build \(build))"
    }

    @ViewBuilder
    private var copyBlock: some View {
        Text("FlatNote is a place to write things down.")
        Text("Every note is an ordinary Markdown file: formatting you can see, written with characters you can type. Your notes live in iCloud or in a local folder on this device. FlatNote stores no separate copy.")
        Text("There is no account because there is nothing an account would do for you. FlatNote collects nothing: no ads, no tracking, no analytics.")
        Text("If you ever stop using FlatNote, your notes remain ordinary files, readable in any editor, on any device.")
    }

    @ViewBuilder
    private var creditBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(versionLine)
            Text("Made by aftrveil.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    var body: some View {
        #if os(macOS)
        // A real About window: content-hugging height, dismissed by the
        // window's own controls — no confirmation-style button.
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Spacer()
            }
            Text("Well, what is FlatNote?")
                .font(.title2.bold())
            copyBlock
                .font(.body)
            creditBlock
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Well, what is FlatNote?")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 30) {
                    copyBlock
                }
                .font(.body)

                creditBlock
                    .padding(.top, 4)

                Button {
                    dismiss()
                } label: {
                    Text("Understood")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .padding(.top, 6)
            }
            .padding(24)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("Close")
        }
        .presentationDetents([.large, .medium])
        #endif
    }
}

// MARK: - Settings

struct SettingsView: View {
    let noteCount: Int
    let exportZipURL: URL?
    let iCloudAvailable: Bool
    let onRestoreWelcome: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingAbout = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Notes", value: "\(noteCount)")
                    LabeledContent("Storage", value: iCloudAvailable ? "iCloud" : "This device")
                } header: {
                    Text("Library")
                } footer: {
                    Text(iCloudAvailable
                        ? "Your notes are files in your iCloud, available on every device signed in with your Apple ID."
                        : "Your notes are files stored on this device. Sign in to iCloud to have them on all your devices.")
                }

                if let exportZipURL {
                    Section {
                        ShareLink(item: exportZipURL) {
                            Label("Export All Notes", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text("Export")
                    } footer: {
                        Text("Share or save your whole library as one zip: every note as a .md file, with folders and images included. Your notes are also available in the Files app under FlatNote.")
                    }
                }

                Section {
                    Button {
                        onRestoreWelcome()
                    } label: {
                        Label("Restore Welcome Note", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Welcome Note")
                } footer: {
                    Text("Brings back the \"Welcome to FlatNote\" guide. If one already exists, it is added as a new copy so your edits are kept.")
                }

                Section {
                    Button {
                        showingAbout = true
                    } label: {
                        Label("What is FlatNote?", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Philosophy")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
        #if os(macOS)
        // Without an explicit frame the List collapses to zero height inside
        // a macOS sheet.
        .frame(minWidth: 440, minHeight: 480)
        #endif
    }
}

// MARK: - Note Card

/// A library card plus its visible actions: a ⋯ menu always shown on iOS and
/// revealed on hover on macOS. The right-click / long-press context menu stays
/// as a secondary path.
private struct NoteCardCell: View {
    let note: NoteFile
    let previewLines: [String]
    let thumbnail: URL?
    let isPinned: Bool
    let folders: [String]
    /// Show the note's folder on the card (the All view; folder views know).
    let showsFolder: Bool
    /// Deferred: menu content is only built when the menu opens, so the export
    /// copy is not created for every card on every refresh.
    let exportURL: () -> URL
    let onOpen: () -> Void
    let onRename: () -> Void
    let onTogglePin: () -> Void
    let onMove: (String?) -> Void
    let onDelete: () -> Void

    #if os(macOS)
    @State private var isHovering = false
    #endif

    private var menuVisible: Bool {
        #if os(macOS)
        return isHovering
        #else
        return true
        #endif
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: onTogglePin) {
            Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
        }
        Button(action: onRename) {
            Label("Rename", systemImage: "pencil")
        }
        if !folders.isEmpty || note.folder != nil {
            Menu {
                if note.folder != nil {
                    Button("Notes") { onMove(nil) }
                }
                ForEach(folders.filter { $0 != note.folder }, id: \.self) { folder in
                    Button(folder) { onMove(folder) }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
        }
        ShareLink(item: exportURL()) {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }

    var body: some View {
        NoteCard(note: note, previewLines: previewLines, thumbnail: thumbnail,
                 isPinned: isPinned, folderTag: showsFolder ? note.folder : nil)
            .onTapGesture(perform: onOpen)
            .overlay(alignment: .topTrailing) {
                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .opacity(menuVisible ? 1 : 0)
                .accessibilityLabel("Note Actions")
            }
            #if os(macOS)
            .onHover { isHovering = $0 }
            #endif
            .contextMenu { actions }
    }
}

/// One preview line, rendered rather than described: headings come back
/// semibold, checkboxes as boxes, bullets as bullets, inline Markdown styled.
private struct PreviewLineView: View {
    let line: String

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    var body: some View {
        if let heading = line.firstMatch(of: /^#{1,6}\s+(.*)$/) {
            Text(inline(String(heading.1)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else if let task = line.firstMatch(of: /^[-*+]\s+\[([ xX])\]\s+(.*)$/) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: task.1 == " " ? "square" : "checkmark.square.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(inline(String(task.2)))
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .lineLimit(1)
            }
        } else if let bullet = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(inline(String(bullet.1)))
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .lineLimit(1)
            }
        } else if let quote = line.firstMatch(of: /^>\s?(.*)$/) {
            Text(inline(String(quote.1)))
                .font(.caption.italic())
                .foregroundStyle(Color.primary.opacity(0.75))
                .lineLimit(1)
        } else {
            Text(inline(line))
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.75))
                .lineLimit(2)
        }
    }
}

struct NoteCard: View {
    let note: NoteFile
    let previewLines: [String]
    var thumbnail: URL? = nil
    var isPinned: Bool = false
    /// Folder name shown on the card in the All view.
    var folderTag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title first: the primary scanning position. Any image sits
            // beneath it.
            Text(note.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let thumbnail, let image = PlatformImage(contentsOfFile: thumbnail.path) {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !previewLines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                        PreviewLineView(line: line)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(note.modifiedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let folderTag {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(folderTag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Pinned")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        #if os(macOS)
        // regularMaterial reads as flat gray over the Mac window background,
        // inverting the iOS scheme (white cards on gray). Use the text
        // background color: white in light mode, adaptive in dark.
        .background(Color(nsColor: .textBackgroundColor))
        #else
        .background(.regularMaterial)
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
