import SwiftUI
import UniformTypeIdentifiers

struct NoteLibraryView: View {
    @State private var store = NoteStore()
    @State private var selectedNote: NoteFile?
    @State private var searchText = ""
    @State private var showingNewNoteAlert = false
    @State private var showingImporter = false
    @State private var newNoteName = ""

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
            .searchable(text: $searchText, prompt: "Search Notes")
            .navigationDestination(item: $selectedNote) { note in
                EditorView(store: store, note: note)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { showingImporter = true } label: {
                            Image(systemName: "folder")
                        }
                        Button { showingNewNoteAlert = true } label: {
                            Image(systemName: "plus")
                        }
                    }
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
