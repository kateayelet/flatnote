import SwiftUI

struct ContentView: View {
    @StateObject private var fileStore = MarkdownFileStore()
    @State private var selectedFile: MarkdownFile?
    @State private var showingFileList = false
    @State private var showingNewFileAlert = false
    @State private var newFileName = ""
    @State private var showingShareSheet = false
    var body: some View {
        NavigationStack {
            EditorView(fileStore: fileStore, currentFile: $selectedFile)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingFileList = true }) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(selectedFile?.name ?? "Veil")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if selectedFile != nil {
                            Button(action: { showingShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.primary)
                            }
                        }
                        Button(action: { showingNewFileAlert = true }) {
                            Image(systemName: "plus")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingFileList) {
                FileListView(
                    fileStore: fileStore,
                    selectedFile: $selectedFile,
                    isPresented: $showingFileList
                )
            }
            .alert("New File", isPresented: $showingNewFileAlert) {
                TextField("filename.md", text: $newFileName)
                Button("Create") {
                    let name = newFileName.hasSuffix(".md") ? newFileName : newFileName + ".md"
                    if !name.isEmpty && name != ".md" {
                        let file = fileStore.createFile(name: name)
                        selectedFile = file
                    }
                    newFileName = ""
                }
                Button("Cancel", role: .cancel) { newFileName = "" }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let file = selectedFile {
                    ShareSheet(activityItems: [file.url])
                }
            }
            .onAppear {
                fileStore.loadFiles()
                if fileStore.files.isEmpty {
                    if let welcome = fileStore.createWelcomeFileIfNeeded() {
                        selectedFile = welcome
                    }
                }
                if selectedFile == nil, let first = fileStore.files.first {
                    selectedFile = first
                }
            }
        }
    }
}
