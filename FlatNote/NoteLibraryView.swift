import SwiftUI
import UniformTypeIdentifiers

struct NoteLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = NoteStore()
    @State private var selectedNote: NoteFile?
    @State private var searchText = ""
    @State private var showingNewNoteAlert = false
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var newNoteName = ""
    @State private var renamingNote: NoteFile?
    @State private var renameText = ""

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
            ScrollView {
                if filteredNotes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
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
                                    ShareLink(item: note.url) {
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
            .navigationTitle("Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            #if DEBUG
            .onAppear {
                // UI-inspection hook: launch with SIMCTL_CHILD_FLATNOTE_OPEN_FIRST=1
                // to jump straight into the first note for screenshots.
                if ProcessInfo.processInfo.environment["FLATNOTE_OPEN_FIRST"] == "1",
                   selectedNote == nil, let first = store.notes.first {
                    selectedNote = first
                }
            }
            #endif
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Notes"
            )
            .navigationDestination(item: $selectedNote) { note in
                EditorView(store: store, note: note)
            }
            .onChange(of: scenePhase) { _, phase in
                // Pick up notes added or removed outside the app.
                if phase == .active { store.loadNotes() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.primary)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .tint(.primary)
                    Button { showingNewNoteAlert = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .tint(.primary)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    store.importFile(from: url)
                }
            }
            .alert("New Note", isPresented: $showingNewNoteAlert) {
                TextField("filename", text: $newNoteName)
                Button("Create") {
                    let name = newNoteName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        let fullName = name.hasSuffix(".md") ? name : name + ".md"
                        if let note = store.createNote(name: fullName) {
                            selectedNote = note
                        }
                    }
                    newNoteName = ""
                }
                Button("Cancel", role: .cancel) { newNoteName = "" }
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
                SettingsView(noteCount: store.notes.count, noteURLs: store.notes.map(\.url))
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
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    LabeledContent("Notes", value: "\(noteCount)")
                    LabeledContent("Stored", value: "On this device")
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
                    .lineLimit(5)
            }

            Spacer(minLength: 0)
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
