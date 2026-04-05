import SwiftUI

struct FileListView: View {
    @ObservedObject var fileStore: MarkdownFileStore
    @Binding var selectedFile: MarkdownFile?
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var showingNewFileAlert = false
    @State private var newFileName = ""

    private var filteredFiles: [MarkdownFile] {
        if searchText.isEmpty { return fileStore.files }
        return fileStore.files.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            (fileStore.readContent(of: $0)).localizedCaseInsensitiveContains(searchText)
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredFiles) { file in
                            NoteCard(file: file, preview: fileStore.readContent(of: file))
                                .onTapGesture {
                                    selectedFile = file
                                    isPresented = false
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        if selectedFile?.id == file.id { selectedFile = nil }
                                        fileStore.deleteFile(file)
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
                .background(Color(.systemGroupedBackground))

                // Bottom bar -- thumb zone
                HStack {
                    Button(action: { isPresented = false }) {
                        Text("Done")
                            .fontWeight(.medium)
                    }
                    Spacer()
                    Button(action: { showingNewFileAlert = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Color(.systemBackground)
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: -2)
                )
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $searchText, prompt: "Search Notes")
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .alert("New Note", isPresented: $showingNewFileAlert) {
                TextField("filename", text: $newFileName)
                Button("Create") {
                    let name = newFileName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        let fullName = name.hasSuffix(".md") ? name : name + ".md"
                        let file = fileStore.createFile(name: fullName)
                        selectedFile = file
                        isPresented = false
                    }
                    newFileName = ""
                }
                Button("Cancel", role: .cancel) { newFileName = "" }
            }
        }
    }
}

struct NoteCard: View {
    let file: MarkdownFile
    let preview: String

    private var title: String {
        let name = file.name.replacingOccurrences(of: ".md", with: "")
        return name.isEmpty ? "Untitled" : name
    }

    private var previewText: String {
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let maxChars = 120
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars)) + "..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.headline, design: .default))
                .foregroundColor(.primary)
                .lineLimit(2)

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(.caption, design: .default))
                    .foregroundColor(.secondary)
                    .lineLimit(5)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}
