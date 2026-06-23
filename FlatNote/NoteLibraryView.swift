import SwiftUI
import UniformTypeIdentifiers

struct NoteLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = NoteStore()
    @State private var selectedNote: NoteFile?
    @State private var newNoteID: URL?
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var renamingNote: NoteFile?
    @State private var renameText = ""

    private func createAndOpenNote() {
        if let note = store.createBlankNote() {
            newNoteID = note.id
            selectedNote = note
        }
    }

    private var filteredNotes: [NoteFile] {
        if searchText.isEmpty { return store.notes }
        return store.notes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            store.readContent(of: $0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.notes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } description: {
                        Text("Your notes will appear here. Create one to get started.")
                    } actions: {
                        Button("New Note") { createAndOpenNote() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filteredNotes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredNotes) { note in
                            NoteCard(note: note, preview: store.preview(for: note))
                                .onTapGesture { selectedNote = note }
                                .contextMenu {
                                    Button {
                                        renameText = note.displayName
                                        renamingNote = note
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    ShareLink(item: store.markdownExportURL(for: note)) {
                                        Label("Export", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        store.deleteNote(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            #if DEBUG
            .onAppear {
                // UI-inspection hook: launch with SIMCTL_CHILD_FLATNOTE_OPEN_FIRST=1
                // to jump straight into the first note for screenshots. Notes load
                // asynchronously, so retry briefly until one is available.
                if ProcessInfo.processInfo.environment["FLATNOTE_OPEN_FIRST"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if selectedNote == nil, let first = store.notes.first {
                            selectedNote = first
                        }
                    }
                }
            }
            #endif
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Notes"
            )
            .navigationDestination(item: $selectedNote) { note in
                EditorView(store: store, note: note, isNew: note.id == newNoteID)
            }
            .onChange(of: scenePhase) { _, phase in
                // Pick up notes added or removed outside the app.
                if phase == .active { store.loadNotes() }
            }
            .onOpenURL { url in
                // A markdown file was tapped in Files, AirDrop, a share sheet,
                // etc. Open it (in place if it is already ours, otherwise as an
                // imported copy) instead of just launching to the library.
                if let note = store.openIncomingFile(url) {
                    newNoteID = nil
                    selectedNote = note
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { createAndOpenNote() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .tint(.primary)
                }
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
                    noteURLs: store.markdownExportURLs(),
                    iCloudAvailable: store.iCloudAvailable
                )
            }
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

// MARK: - Settings

struct SettingsView: View {
    let noteCount: Int
    let noteURLs: [URL]
    let iCloudAvailable: Bool
    @Environment(\.dismiss) private var dismiss

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
                    LabeledContent("Sync", value: iCloudAvailable ? "iCloud" : "This device only")
                } header: {
                    Text("Library")
                } footer: {
                    Text(iCloudAvailable
                        ? "Your notes sync across your devices through iCloud, signed in with your Apple ID."
                        : "Notes are stored on this device. Sign in to iCloud to sync them across your devices.")
                }

                if !noteURLs.isEmpty {
                    Section {
                        ShareLink(items: noteURLs) {
                            Label("Export All Notes", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text("Export")
                    } footer: {
                        Text("Share or save every note as .md files. Your notes are also available in the Files app under FlatNote.")
                    }
                }

                Section {
                    Text("FlatNote keeps everything as plain .md files. They are yours: portable, future-proof, and readable in any app. No proprietary formats, no lock-in.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
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
        }
    }
}

// MARK: - Note Card

struct NoteCard: View {
    let note: NoteFile
    let preview: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            Spacer(minLength: 0)

            Text(note.modifiedDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
