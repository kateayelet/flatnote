//
//  FlatNoteTests.swift
//  FlatNoteTests
//
//  Created by Kate Ayelet Benediktsson on 5/14/26.
//

import Testing
import Foundation
import JavaScriptCore
@testable import FlatNote

// MARK: - NoteFile Tests

struct NoteFileTests {

    @Test func displayNameStripsExtension() {
        let url = URL(fileURLWithPath: "/tmp/My Note.md")
        let note = NoteFile(id: url, name: "My Note.md", modifiedDate: Date())
        #expect(note.displayName == "My Note")
    }

    @Test func displayNameStripsMarkdownExtension() {
        let url = URL(fileURLWithPath: "/tmp/Research.markdown")
        let note = NoteFile(id: url, name: "Research.markdown", modifiedDate: Date())
        #expect(note.displayName == "Research")
    }

    @Test func displayNameStripsTxtExtension() {
        let url = URL(fileURLWithPath: "/tmp/Draft.txt")
        let note = NoteFile(id: url, name: "Draft.txt", modifiedDate: Date())
        #expect(note.displayName == "Draft")
    }

    @Test func displayNameHandlesNoExtension() {
        let url = URL(fileURLWithPath: "/tmp/README")
        let note = NoteFile(id: url, name: "README", modifiedDate: Date())
        #expect(note.displayName == "README")
    }

    @Test func displayNameHandlesMultipleDots() {
        let url = URL(fileURLWithPath: "/tmp/my.cool.note.md")
        let note = NoteFile(id: url, name: "my.cool.note.md", modifiedDate: Date())
        #expect(note.displayName == "my.cool.note")
    }

    @Test func urlMatchesId() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let note = NoteFile(id: url, name: "test.md", modifiedDate: Date())
        #expect(note.url == url)
    }

    @Test func identityIsURL() {
        let url1 = URL(fileURLWithPath: "/tmp/a.md")
        let url2 = URL(fileURLWithPath: "/tmp/b.md")
        let note1 = NoteFile(id: url1, name: "a.md", modifiedDate: Date())
        let note2 = NoteFile(id: url2, name: "b.md", modifiedDate: Date())
        #expect(note1 != note2)

        let note1copy = NoteFile(id: url1, name: "a.md", modifiedDate: Date())
        #expect(note1 == note1copy)
    }
}

// MARK: - NoteStore Tests (filesystem integration)

struct NoteStoreTests {

    private func makeTempStore() -> (NoteStore, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("flatnote-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (NoteStore(directory: tmp), tmp)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func createNoteWritesFile() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "test.md")!
        #expect(FileManager.default.fileExists(atPath: note.url.path))
        #expect(store.notes.count >= 1)
    }

    @Test func readContentReturnsWrittenContent() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "hello.md")!
        store.saveContent("# Hello World", to: note)
        let content = store.readContent(of: note)
        #expect(content == "# Hello World")
    }

    @Test func readContentReturnsEmptyForMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).md")
        let note = NoteFile(id: url, name: "gone.md", modifiedDate: Date())
        let store = NoteStore(directory: FileManager.default.temporaryDirectory)
        #expect(store.readContent(of: note) == "")
    }

    @Test func deleteNoteRemovesFile() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "delete-me.md")!
        #expect(FileManager.default.fileExists(atPath: note.url.path))

        store.deleteNote(note)
        #expect(!FileManager.default.fileExists(atPath: note.url.path))
        #expect(!store.notes.contains(where: { $0.id == note.id }))
    }

    @Test func previewTruncatesLongContent() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "long.md")!
        let longText = String(repeating: "a", count: 200)
        store.saveContent(longText, to: note)

        let preview = store.preview(for: note)
        #expect(preview.count == 123) // 120 chars + "..."
        #expect(preview.hasSuffix("..."))
    }

    @Test func previewReturnsShortContentUnchanged() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "short.md")!
        store.saveContent("Short note.", to: note)

        let preview = store.preview(for: note)
        #expect(preview == "Short note.")
    }

    @Test func previewReturnsEmptyForEmptyNote() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "empty.md")!
        let preview = store.preview(for: note)
        #expect(preview == "")
    }

    @Test func loadNotesFindsMarkdownFiles() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        try! "# A".write(to: tmp.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try! "# B".write(to: tmp.appendingPathComponent("b.markdown"), atomically: true, encoding: .utf8)
        try! "C".write(to: tmp.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        try! "{}".write(to: tmp.appendingPathComponent("d.json"), atomically: true, encoding: .utf8)

        store.loadNotes()
        let names = store.notes.map(\.name)
        #expect(names.contains("a.md"))
        #expect(names.contains("b.markdown"))
        #expect(names.contains("c.txt"))
        #expect(!names.contains("d.json"))
    }

    @Test func loadNotesSortsByModifiedDateDescending() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let older = tmp.appendingPathComponent("older.md")
        let newer = tmp.appendingPathComponent("newer.md")
        try! "old".write(to: older, atomically: true, encoding: .utf8)
        // Set older file's date to the past
        try! FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: older.path
        )
        try! "new".write(to: newer, atomically: true, encoding: .utf8)

        store.loadNotes()
        #expect(store.notes.first?.name == "newer.md")
        #expect(store.notes.last?.name == "older.md")
    }

    @Test func createNoteInsertsAtFront() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        _ = store.createNote(name: "first.md")
        _ = store.createNote(name: "second.md")
        #expect(store.notes.first?.name == "second.md")
    }

    // MARK: Error surfacing

    @Test func successfulCreateLeavesNoError() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        _ = store.createNote(name: "ok.md")
        #expect(store.lastError == nil)
    }

    @Test func createNoteFailureReturnsNilAndSetsError() {
        // Point the store at a path that cannot be written (a child of a non-directory).
        let store = NoteStore(directory: URL(fileURLWithPath: "/dev/null/cannot-exist"))

        let note = store.createNote(name: "doomed.md")
        #expect(note == nil)
        #expect(store.lastError != nil)
        #expect(store.notes.isEmpty)
    }

    @Test func saveFailureSetsError() {
        let store = NoteStore(directory: FileManager.default.temporaryDirectory)
        let badNote = NoteFile(
            id: URL(fileURLWithPath: "/dev/null/cannot-exist/x.md"),
            name: "x.md",
            modifiedDate: Date()
        )
        store.saveContent("data", to: badNote)
        #expect(store.lastError != nil)
    }

    // MARK: Non-destructive import naming

    @Test func uniqueDestinationAvoidsCollision() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        _ = store.createNote(name: "dup.md")
        let dest = store.uniqueDestination(for: "dup.md")
        #expect(dest.lastPathComponent == "dup 2.md")

        try! "x".write(to: tmp.appendingPathComponent("dup 2.md"), atomically: true, encoding: .utf8)
        #expect(store.uniqueDestination(for: "dup.md").lastPathComponent == "dup 3.md")
    }

    @Test func uniqueDestinationWithoutExtension() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        try! "x".write(to: tmp.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        #expect(store.uniqueDestination(for: "README").lastPathComponent == "README 2")
    }

    @Test func uniqueDestinationNoCollisionKeepsName() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        #expect(store.uniqueDestination(for: "fresh.md").lastPathComponent == "fresh.md")
    }

    // MARK: Markdown export

    @Test func exportOfMarkdownNoteUsesOriginalFile() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "keep.md")!
        #expect(store.markdownExportURL(for: note) == note.url)
    }

    @Test func exportOfTxtNoteBecomesMarkdown() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let txt = tmp.appendingPathComponent("plain.txt")
        try! "hello".write(to: txt, atomically: true, encoding: .utf8)
        store.loadNotes()
        let note = store.notes.first { $0.name == "plain.txt" }!

        let export = store.markdownExportURL(for: note)
        #expect(export.pathExtension == "md")
        #expect((try? String(contentsOf: export, encoding: .utf8)) == "hello")
    }

    @Test func titleFromContentUsesFirstNonEmptyLine() {
        #expect(NoteStore.titleFromContent("# Grocery list\nmilk\neggs") == "Grocery list")
        #expect(NoteStore.titleFromContent("\n\n  - first real line") == "first real line")
        #expect(NoteStore.titleFromContent("   \n\t") == "")
        #expect(NoteStore.titleFromContent("a/b: c") == "a-b- c")
    }

    @Test func renameToFirstLineRenamesBlankNote() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createBlankNote()!
        #expect(note.displayName == "New Note")
        store.saveContent("# Shopping\nmilk", to: note)
        let renamed = store.renameToFirstLine(note, content: "# Shopping\nmilk")
        #expect(renamed.displayName == "Shopping")
        #expect(FileManager.default.fileExists(atPath: renamed.url.path))
        #expect(!FileManager.default.fileExists(atPath: note.url.path))
    }

    @Test func createBlankNoteDeduplicates() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let a = store.createBlankNote()!
        let b = store.createBlankNote()!
        #expect(a.url != b.url)
    }

    @Test func strippedMarkdownRemovesSyntax() {
        let md = "# Title\n\n- a **bold** item\n> quote\n[link](http://x)\n`code`"
        let plain = NoteStore.strippedMarkdown(md)
        #expect(!plain.contains("#"))
        #expect(!plain.contains("**"))
        #expect(!plain.contains(">"))
        #expect(!plain.contains("`"))
        #expect(plain.contains("Title"))
        #expect(plain.contains("bold"))
        #expect(plain.contains("link"))
        #expect(!plain.contains("http"))
    }

    @Test func exportAllProducesOnlyMarkdownURLs() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        _ = store.createNote(name: "a.md")
        try! "x".write(to: tmp.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        store.loadNotes()

        let urls = store.markdownExportURLs()
        #expect(urls.count == store.notes.count)
        #expect(urls.allSatisfy { $0.pathExtension == "md" })
    }
}

// MARK: - MarkdownDocument Tests

struct MarkdownDocumentTests {

    @Test func initWithTextPreservesContent() {
        let doc = MarkdownDocument(text: "# Hello")
        #expect(doc.text == "# Hello")
    }

    @Test func defaultInitIsEmpty() {
        let doc = MarkdownDocument()
        #expect(doc.text == "")
    }

    // FileDocument's ReadConfiguration/WriteConfiguration have no public
    // initializers, so the config-based methods cannot be invoked from a unit
    // test. These verify the same UTF-8 serialization contract the document
    // relies on (write does Data(text.utf8); read does String(decoding:as:)).

    @Test func serializationRoundTrip() {
        let original = "# Test\n\nSome **bold** text.\n"
        let doc = MarkdownDocument(text: original)

        let data = Data(doc.text.utf8)
        let decoded = String(decoding: data, as: UTF8.self)
        #expect(decoded == original)
    }

    @Test func serializationHandlesUnicode() {
        let text = "Hebrew: \u{05E9}\u{05DC}\u{05D5}\u{05DD}\nEmoji: \u{1F30D}\n"
        let doc = MarkdownDocument(text: text)

        let data = Data(doc.text.utf8)
        let decoded = String(decoding: data, as: UTF8.self)
        #expect(decoded == text)
    }

    @Test func serializationHandlesEmptyDocument() {
        let doc = MarkdownDocument(text: "")
        let data = Data(doc.text.utf8)
        #expect(data.isEmpty)
    }
}

// MARK: - Markdown renderer (JavaScriptCore)

/// Exercises the real editor renderer (FlatNote/Resources/render.js) in a JS
/// context, so the markdown -> HTML logic is covered without a live WebView.
struct MarkdownRenderTests {

    private func makeRenderer() throws -> (String) -> String {
        let bundle = Bundle(for: NoteStore.self)
        let url = try #require(
            bundle.url(forResource: "render", withExtension: "js"),
            "render.js must be bundled with the app"
        )
        let js = try String(contentsOf: url, encoding: .utf8)
        let ctx = try #require(JSContext())
        ctx.evaluateScript(js)
        return { md in
            ctx.objectForKeyedSubscript("renderMarkdown")?
                .call(withArguments: [md])?.toString() ?? ""
        }
    }

    /// Approximates DOM textContent by removing tags and unescaping entities.
    private func textContent(_ html: String) -> String {
        var out = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true }
            else if ch == ">" { inTag = false }
            else if !inTag { out.append(ch) }
        }
        return out
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    @Test func headingRendersWithoutVisibleHash() throws {
        let render = try makeRenderer()
        let html = render("# Title")
        #expect(html.contains("line-h1"))
        #expect(html.contains("class=\"mk\">#"))   // marker present, hidden via CSS
        #expect(html.contains("Title"))
    }

    @Test func bulletGetsListMarkerClass() throws {
        let render = try makeRenderer()
        #expect(render("- item").contains("list-mk"))
    }

    @Test func uncheckedTaskRendersEmptyBox() throws {
        let render = try makeRenderer()
        let html = render("- [ ] todo")
        #expect(html.contains("task-cb-vis"))
        #expect(!html.contains("task-cb-vis checked"))
    }

    @Test func checkedTaskRendersCheckedBox() throws {
        let render = try makeRenderer()
        #expect(render("- [x] done").contains("task-cb-vis checked"))
    }

    @Test func boldRendersAndDoesNotLeakItalic() throws {
        let render = try makeRenderer()
        let html = render("**bold**")
        #expect(html.contains("md-bold"))
        #expect(html.contains(">bold<"))
        #expect(!html.contains("md-italic"))   // single-pass tokenizer guard
    }

    @Test func htmlIsEscaped() throws {
        let render = try makeRenderer()
        let html = render("a < b & c")
        #expect(html.contains("&lt;"))
        #expect(html.contains("&amp;"))
    }

    @Test func renderedTextContentEqualsSourceLine() throws {
        // The editor's core invariant: stripping tags from a rendered line
        // returns the exact markdown source, which is what keeps cursor
        // offsets aligned with the source string.
        let render = try makeRenderer()
        let cases = [
            "# Title", "## Sub", "- item", "* star", "1. first",
            "- [ ] todo", "- [x] done", "> quote",
            "**bold** and *italic* and ~~strike~~ and `code`",
            "a < b & c", "plain text", "",
        ]
        for md in cases {
            #expect(textContent(render(md)) == md, "textContent must equal source for: \(md)")
        }
    }
}
