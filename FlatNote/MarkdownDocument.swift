import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import WebKit
import AppKit
#endif

struct MarkdownDocument: FileDocument {
    /// Pinned to the type this app itself exports in Info.plist, so a
    /// third-party app claiming .md can never make the document types diverge
    /// from the CFBundleDocumentTypes declaration.
    private static let markdownType = UTType(exportedAs: "net.daringfireball.markdown")

    // Markdown first: untitled documents inherit the first type, so new notes
    // save as .md by default rather than .txt.
    static var readableContentTypes: [UTType] {
        [markdownType, .plainText]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            text = ""
            return
        }

        // Strict decode: refusing a non-UTF-8 file beats opening it lossily
        // and mangling it in place on the first edit.
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return .init(regularFileWithContents: data)
    }
}

#if os(macOS)

// MARK: - Focused-editor plumbing

/// Publishes the key document window's editor so the Edit > Undo / Redo menu
/// commands reach the right web view when several notes are open at once.
struct ActiveEditorKey: FocusedValueKey {
    typealias Value = EditorController
}

extension FocusedValues {
    var activeEditor: EditorController? {
        get { self[ActiveEditorKey.self] }
        set { self[ActiveEditorKey.self] = newValue }
    }
}

// MARK: - Document editor (macOS)

/// A document window's content: the same WKWebView markdown editor the library
/// notes use, but bound to an NSDocument-backed file that is edited in place —
/// wherever it lives. Saving, autosave, Rename, Duplicate, Move To, and Revert
/// all come from the system document machinery.
struct DocumentEditorView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?

    @State private var controller = EditorController()
    @State private var showingFind = false
    @State private var findText = ""
    /// Shared with the View > Outline menu toggle (same defaults key).
    @AppStorage("flatnoteOutlineVisible") private var outlineVisible = true

    private var exportName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Note"
    }

    /// The note's headings, straight from the source text: (line, level, title).
    private struct OutlineItem: Identifiable {
        let id: Int
        let level: Int
        let title: String
    }

    private var outline: [OutlineItem] {
        document.text.components(separatedBy: "\n").enumerated().compactMap { index, line in
            guard let match = line.range(of: "^#{1,6} +", options: .regularExpression) else { return nil }
            let level = line[..<match.upperBound].filter { $0 == "#" }.count
            let title = String(line[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return OutlineItem(id: index, level: level, title: title)
        }
    }

    var body: some View {
        HSplitView {
            if outlineVisible {
                outlinePane
                    .frame(minWidth: 120, idealWidth: 150, maxWidth: 200)
            }
            DocumentWebView(text: $document.text, controller: controller, fileURL: fileURL)
                .frame(minWidth: 420)
        }
        .onAppear { controller.suggestedExportName = exportName }
        .onChange(of: fileURL) { _, _ in controller.suggestedExportName = exportName }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    outlineVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Show or hide the outline")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleFind()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Find in note")
            }
        }
        .safeAreaInset(edge: .top) {
            if showingFind {
                findBar
            }
        }
        .focusedSceneValue(\.activeEditor, controller)
    }

    private var outlinePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OUTLINE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
            if outline.isEmpty {
                VStack {
                    Text("No headings")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(outline) { item in
                    Button {
                        controller.scrollTo(line: item.id)
                    } label: {
                        Text(item.title)
                            .font(item.level == 1 ? .callout.weight(.semibold) : .callout)
                            .lineLimit(1)
                            .padding(.leading, CGFloat(item.level - 1) * 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
    }

    // Mirrors EditorView.findBar (the iOS/library editor); kept in sync by hand.
    private var findBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in note", text: $findText)
                .autocorrectionDisabled()
                .onChange(of: findText) { _, value in
                    controller.setSearch(value)
                }

            if controller.matchCount > 0 {
                Text("\(controller.currentMatch)/\(controller.matchCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if !findText.isEmpty {
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button { controller.previous() } label: { Image(systemName: "chevron.up") }
                .disabled(controller.matchCount == 0)
            Button { controller.next() } label: { Image(systemName: "chevron.down") }
                .disabled(controller.matchCount == 0)
            Button { toggleFind() } label: { Image(systemName: "xmark.circle.fill") }
                .foregroundStyle(.secondary)
        }
        .tint(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func toggleFind() {
        showingFind.toggle()
        if !showingFind {
            findText = ""
            controller.clear()
        }
    }
}

private struct DocumentWebView: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    var fileURL: URL?

    func makeCoordinator() -> DocumentEditorCoordinator {
        DocumentEditorCoordinator(text: $text, controller: controller)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.createWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The struct is recreated on every SwiftUI update; keep the coordinator
        // pointed at the live binding, then reflect external document changes
        // (Revert To, iCloud sync) into the editor. Echoes of the editor's own
        // writes are skipped inside pushContentIfChanged.
        context.coordinator.rebind($text)
        context.coordinator.fileURL = fileURL
        context.coordinator.pushContentIfChanged(text)
    }
}

/// Bridges editor.html to the document binding. Unlike EditorCoordinator (the
/// library/iOS path, which saves through NoteStore), every edit here is written
/// straight into the FileDocument binding: the system marks the document dirty
/// and autosaves it in place, so no debounce or manual flush is needed.
final class DocumentEditorCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var text: Binding<String>
    let controller: EditorController
    private weak var webView: WKWebView?
    private var editorReady = false
    /// The document's on-disk location, kept current by updateNSView so
    /// pasted images land next to the file (and Save As keeps working).
    var fileURL: URL?
    /// What the web editor currently holds, to tell external changes from
    /// echoes of our own binding writes.
    private var webContent: String?

    init(text: Binding<String>, controller: EditorController) {
        self.text = text
        self.controller = controller
        super.init()
    }

    func rebind(_ newBinding: Binding<String>) {
        text = newBinding
    }

    func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        userController.add(self, name: "flatnote")
        config.userContentController = userController
        config.setURLSchemeHandler(AssetSchemeHandler(baseDirectory: { [weak self] in
            self?.fileURL?.deletingLastPathComponent()
        }), forURLScheme: AssetSchemeHandler.scheme)

        let webView = EditorWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        controller.webView = webView
        webView.onPasteImage = { [weak self] data, mime in
            guard let self, let fileURL = self.fileURL else { NSSound.beep(); return }
            if let rel = AssetSchemeHandler.saveImageAsset(data: data, mime: mime, noteURL: fileURL) {
                self.webView?.evaluateJavaScript("insertPastedImage('\(rel)')")
            } else {
                NSSound.beep()
            }
        }

        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources") ??
           Bundle.main.url(forResource: "editor", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        return webView
    }

    // MARK: WKNavigationDelegate

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        editorReady = true
        let content = text.wrappedValue
        webContent = content
        webView.evaluateJavaScript("setContent(`\(EditorCoordinator.escapeForJS(content))`)")
        // First responder before the contenteditable can take keystrokes;
        // SwiftUI does not hand a represented web view focus on its own.
        DispatchQueue.main.async {
            webView.window?.makeFirstResponder(webView)
            webView.evaluateJavaScript("focusEditor()")
        }
    }

    // MARK: Content flow

    func pushContentIfChanged(_ newText: String) {
        guard editorReady, let webView, newText != webContent else { return }
        webContent = newText
        webView.evaluateJavaScript("setContent(`\(EditorCoordinator.escapeForJS(newText))`)")
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "flatnote",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        if action == "contentChanged", let markdown = body["markdown"] as? String {
            webContent = markdown
            if text.wrappedValue != markdown {
                text.wrappedValue = markdown
            }
        }

        if action == "pasteImage",
           let b64 = body["data"] as? String,
           let data = Data(base64Encoded: b64) {
            // An untitled document has nowhere on disk to put the asset yet;
            // the paste is dropped rather than inventing a location.
            guard let fileURL else { NSSound.beep(); return }
            let mime = body["mime"] as? String ?? "image/png"
            if let rel = AssetSchemeHandler.saveImageAsset(data: data, mime: mime, noteURL: fileURL) {
                webView?.evaluateJavaScript("insertPastedImage('\(rel)')")
            } else {
                NSSound.beep()
            }
        }

        if action == "attachImage" {
            // Format > Image…, same pipeline as paste. Untitled documents
            // have nowhere on disk to put the asset yet.
            guard fileURL != nil else { NSSound.beep(); return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.begin { [weak self] response in
                guard let self, response == .OK, let url = panel.url,
                      let data = try? Data(contentsOf: url), let fileURL = self.fileURL else { return }
                let mime: String
                switch url.pathExtension.lowercased() {
                case "jpg", "jpeg": mime = "image/jpeg"
                case "gif": mime = "image/gif"
                case "heic": mime = "image/heic"
                case "webp": mime = "image/webp"
                default: mime = "image/png"
                }
                if let rel = AssetSchemeHandler.saveImageAsset(data: data, mime: mime, noteURL: fileURL) {
                    self.webView?.evaluateJavaScript("insertPastedImage('\(rel)')")
                } else {
                    NSSound.beep()
                }
            }
        }
    }
}

#endif
