import Foundation

struct MarkdownFile: Identifiable, Equatable {
    let id: UUID
    let name: String
    let url: URL
    var modifiedDate: Date

    static func == (lhs: MarkdownFile, rhs: MarkdownFile) -> Bool {
        lhs.id == rhs.id
    }
}

class MarkdownFileStore: ObservableObject {
    @Published var files: [MarkdownFile] = []

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func loadFiles() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            files = contents
                .filter { $0.pathExtension == "md" }
                .compactMap { url -> MarkdownFile? in
                    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let modified = attrs?[.modificationDate] as? Date ?? Date()
                    return MarkdownFile(
                        id: UUID(),
                        name: url.lastPathComponent,
                        url: url,
                        modifiedDate: modified
                    )
                }
                .sorted { $0.modifiedDate > $1.modifiedDate }
        } catch {
            files = []
        }
    }

    func createWelcomeFileIfNeeded() -> MarkdownFile? {
        let welcomeName = "Welcome to Veil.md"
        let url = documentsURL.appendingPathComponent(welcomeName)
        if FileManager.default.fileExists(atPath: url.path) { return nil }

        let content = """
# Welcome to Veil

Veil is a plain markdown editor. Everything you write here is saved as a **.md** file -- plain text with simple formatting.

## Why Markdown?

Markdown files are plain text. They will never corrupt, never require a specific app to open, and never become unreadable. A .md file you write today will open in any text editor, on any device, decades from now. No proprietary formats. No lock-in. Your words belong to you.

## Syntax

### Text

*italic* -- wrap with single asterisks
**bold** -- wrap with double asterisks
***bold italic*** -- wrap with triple asterisks
~~strikethrough~~ -- wrap with double tildes
`inline code` -- wrap with backticks

### Headings

# Heading 1
## Heading 2
### Heading 3

Use 1-6 hash marks followed by a space.

### Lists

- Bullet item (dash + space)
- Another item
  - Indent with two spaces for nesting

1. Numbered item
2. Another item

- [ ] Unchecked task
- [x] Completed task

### Other

> Blockquotes start with >

[Link text](https://example.com)

Use three dashes for a horizontal rule:

---

Wrap code blocks with triple backticks:

```
code goes here
```

## Getting started

Tap the **+** button to create a new note. Tap the document icon to browse your notes. Everything saves automatically as you type.
"""
        try? content.write(to: url, atomically: true, encoding: .utf8)
        let file = MarkdownFile(id: UUID(), name: welcomeName, url: url, modifiedDate: Date())
        files.insert(file, at: 0)
        return file
    }

    func createFile(name: String) -> MarkdownFile {
        let url = documentsURL.appendingPathComponent(name)
        try? "".write(to: url, atomically: true, encoding: .utf8)
        let file = MarkdownFile(id: UUID(), name: name, url: url, modifiedDate: Date())
        files.insert(file, at: 0)
        return file
    }

    func readContent(of file: MarkdownFile) -> String {
        (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
    }

    func saveContent(_ content: String, to file: MarkdownFile) {
        try? content.write(to: file.url, atomically: true, encoding: .utf8)
    }

    func deleteFile(_ file: MarkdownFile) {
        try? FileManager.default.removeItem(at: file.url)
        files.removeAll { $0.id == file.id }
    }
}
