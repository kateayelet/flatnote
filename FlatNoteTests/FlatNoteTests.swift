//
//  FlatNoteTests.swift
//  FlatNoteTests
//
//  Created by Kate Ayelet Benediktsson on 5/14/26.
//

import Testing
import Foundation
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

        let note = store.createNote(name: "test.md")
        #expect(FileManager.default.fileExists(atPath: note.url.path))
        #expect(store.notes.count >= 1)
    }

    @Test func readContentReturnsWrittenContent() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "hello.md")
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

        let note = store.createNote(name: "delete-me.md")
        #expect(FileManager.default.fileExists(atPath: note.url.path))

        store.deleteNote(note)
        #expect(!FileManager.default.fileExists(atPath: note.url.path))
        #expect(!store.notes.contains(where: { $0.id == note.id }))
    }

    @Test func previewTruncatesLongContent() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "long.md")
        let longText = String(repeating: "a", count: 200)
        store.saveContent(longText, to: note)

        let preview = store.preview(for: note)
        #expect(preview.count == 123) // 120 chars + "..."
        #expect(preview.hasSuffix("..."))
    }

    @Test func previewReturnsShortContentUnchanged() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "short.md")
        store.saveContent("Short note.", to: note)

        let preview = store.preview(for: note)
        #expect(preview == "Short note.")
    }

    @Test func previewReturnsEmptyForEmptyNote() {
        let (store, tmp) = makeTempStore()
        defer { cleanup(tmp) }

        let note = store.createNote(name: "empty.md")
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

    @Test func fileWrapperRoundTrip() throws {
        let original = "# Test\n\nSome **bold** text.\n"
        let doc = MarkdownDocument(text: original)

        let wrapper = try doc.fileWrapper(configuration: .init())
        let data = wrapper.regularFileContents!
        let decoded = String(data: data, as: UTF8.self)
        #expect(decoded == original)
    }

    @Test func fileWrapperHandlesUnicode() throws {
        let text = "Hebrew: \u{05E9}\u{05DC}\u{05D5}\u{05DD}\nEmoji: \u{1F30D}\n"
        let doc = MarkdownDocument(text: text)

        let wrapper = try doc.fileWrapper(configuration: .init())
        let data = wrapper.regularFileContents!
        let decoded = String(data: data, as: UTF8.self)
        #expect(decoded == text)
    }

    @Test func fileWrapperHandlesEmptyDocument() throws {
        let doc = MarkdownDocument(text: "")
        let wrapper = try doc.fileWrapper(configuration: .init())
        let data = wrapper.regularFileContents!
        #expect(data.isEmpty)
    }
}
