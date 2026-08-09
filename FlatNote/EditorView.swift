import SwiftUI
import WebKit
#if canImport(UIKit)
import UIKit
import PhotosUI
import PencilKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Bridges the SwiftUI find bar to the editor's web view.
@Observable
final class EditorController {
    weak var webView: WKWebView?
    var matchCount = 0
    var currentMatch = 0
    /// Called when the editor closes, to flush and title the note.
    var onClose: (() -> Void)?

    func setSearch(_ query: String) {
        guard let webView else { return }
        let escaped = EditorCoordinator.escapeForJS(query)
        webView.evaluateJavaScript("setSearch(`\(escaped)`)") { [weak self] result, _ in
            let count = (result as? Int) ?? 0
            self?.matchCount = count
            self?.currentMatch = count > 0 ? 1 : 0
        }
    }

    func next() {
        webView?.evaluateJavaScript("searchNext()") { [weak self] result, _ in
            if let index = result as? Int { self?.currentMatch = index }
        }
    }

    func previous() {
        webView?.evaluateJavaScript("searchPrev()") { [weak self] result, _ in
            if let index = result as? Int { self?.currentMatch = index }
        }
    }

    func clear() {
        matchCount = 0
        currentMatch = 0
        webView?.evaluateJavaScript("clearSearch()")
    }

    /// The web editor owns the undo stack (it intercepts all input), so the
    /// macOS Edit menu forwards into it via the focused editor value.
    func undo() { webView?.evaluateJavaScript("undo()") }
    func redo() { webView?.evaluateJavaScript("redo()") }

    /// Menu-bar formatting (Mac Format / Paragraph menus): invokes the same
    /// named actions the touch toolbar uses.
    func format(_ name: String) { webView?.evaluateJavaScript("runFormat('\(name)')") }

    /// Outline navigation: scroll the given source line into view.
    func scrollTo(line: Int) { webView?.evaluateJavaScript("scrollToLine(\(line))") }

    #if os(macOS)
    /// Suggested filename for exports, set by the owning document view.
    var suggestedExportName = "Note"

    /// File > Export as PDF: snapshots the rendered note (the full scrollable
    /// content, Safari-style single tall page) to a user-chosen location.
    func exportPDF() {
        guard let webView else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedExportName + ".pdf"
        panel.canCreateDirectories = true
        let complete: (URL) -> Void = { [weak webView] url in
            let config = WKPDFConfiguration()
            webView?.createPDF(configuration: config) { result in
                do {
                    try result.get().write(to: url)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Could not export the PDF"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { complete(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            complete(url)
        }
    }

    /// File > Print: a paginated print operation over the rendered note. The
    /// print dialog's own PDF button is the second road to a PDF.
    func printNote() {
        guard let webView else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = webView.window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
    #endif
}

/// Serves local images referenced by a note ("assets/x.png") to the web
/// editor via flatnote-asset:///, resolving against the note's own directory.
/// Containment-checked so a crafted path cannot read outside it.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "flatnote-asset"
    private let baseDirectory: () -> URL?

    init(baseDirectory: @escaping () -> URL?) {
        self.baseDirectory = baseDirectory
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let base = baseDirectory() else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let relative = (url.path.removingPercentEncoding ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file = base.appendingPathComponent(relative).standardizedFileURL
        guard file.path.hasPrefix(base.standardizedFileURL.path + "/") || file.path == base.standardizedFileURL.path,
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime: String
        switch file.pathExtension.lowercased() {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "gif": mime = "image/gif"
        case "heic": mime = "image/heic"
        case "webp": mime = "image/webp"
        default: mime = "image/png"
        }
        task.didReceive(URLResponse(url: url, mimeType: mime,
                                    expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Writes pasted image bytes as a real file next to the note:
    /// assets/<note-name>/img-<timestamp>.<ext>, and returns the relative
    /// path to reference in the markdown. The .md stays plain text; any
    /// other Markdown app renders the same note.
    static func saveImageAsset(data: Data, mime: String, noteURL: URL) -> String? {
        let ext: String
        switch mime {
        case "image/jpeg": ext = "jpg"
        case "image/gif": ext = "gif"
        case "image/heic": ext = "heic"
        case "image/webp": ext = "webp"
        default: ext = "png"
        }
        // Folder named for the note, sanitized to stay a clean markdown path
        // (the link syntax cannot hold spaces).
        let noteName = noteURL.deletingPathExtension().lastPathComponent
        let safe = noteName.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        let dirName = String(safe)
        let dir = noteURL.deletingLastPathComponent()
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent(dirName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let stamp = formatter.string(from: Date())
            var name = "img-\(stamp).\(ext)"
            var counter = 2
            while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
                name = "img-\(stamp)-\(counter).\(ext)"
                counter += 1
            }
            try data.write(to: dir.appendingPathComponent(name))
            return "assets/\(dirName)/\(name)"
        } catch {
            return nil
        }
    }
}

struct EditorView: View {
    let store: NoteStore
    let note: NoteFile
    var isNew: Bool = false
    /// iOS: asks the library to run its rename flow for this note. macOS
    /// document windows already rename from the title bar via NSDocument.
    var onRequestRename: (() -> Void)? = nil

    @State private var controller = EditorController()
    @State private var showingFind = false
    @State private var findText = ""

    var body: some View {
        EditorWebView(store: store, note: note, controller: controller, isNew: isNew)
            #if os(iOS)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(note.displayName)
            #else
            .navigationTitle(note.displayName)
            #endif
            #if os(iOS)
            .toolbarTitleMenu {
                if let onRequestRename {
                    Button {
                        onRequestRename()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
            }
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleFind()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .tint(.primary)
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        toggleFind()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Find in note")
                }
                #endif
            }
            .safeAreaInset(edge: .top) {
                if showingFind {
                    findBar
                }
            }
            .onDisappear { controller.onClose?() }
            #if DEBUG
            .onAppear {
                // Screenshot hook: launch with SIMCTL_CHILD_FLATNOTE_FIND=<term>
                // to auto-open find and highlight matches.
                if let term = ProcessInfo.processInfo.environment["FLATNOTE_FIND"], !term.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showingFind = true
                        findText = term
                        controller.setSearch(term)
                    }
                }
            }
            #endif
    }

    private var findBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in note", text: $findText)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
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

// MARK: - WKWebView subclass

#if os(iOS)
/// A web view that exposes a hook for an input accessory, reserved for future
/// native keyboard chrome. The formatting toolbar itself lives in editor.html.
final class EditorWKWebView: WKWebView {}
#else
/// On macOS a WKWebView embedded in an NSViewRepresentable does not become the
/// window's first responder on its own, so the contenteditable editor never
/// receives keystrokes. Advertising that it accepts first responder lets the
/// coordinator hand it focus once it is in a window.
final class EditorWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    /// Set by the coordinator. macOS WebKit does not hand pasteboard images to
    /// the JS paste event, so an image paste is intercepted natively here and
    /// routed to the same save-asset path; anything else falls through.
    var onPasteImage: ((Data, String) -> Void)?

    /// True if the pasteboard held an image (and no text) and it was routed
    /// to the host. Text-plus-image clipboards (e.g. copied web content) fall
    /// through to WebKit's own paste.
    private func handleImagePasteIfAvailable() -> Bool {
        let pb = NSPasteboard.general
        guard pb.string(forType: .string) == nil, let onPasteImage else { return false }
        if let png = pb.data(forType: .png) {
            onPasteImage(png, "image/png")
            return true
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            onPasteImage(png, "image/png")
            return true
        }
        return false
    }

    /// WKWebView consumes Cmd+V inside its own key handling, so the paste:
    /// responder action never fires for the key press; the key equivalent is
    /// the reliable interception point.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v",
           handleImagePasteIfAvailable() {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Menu bar Edit > Paste routes here via the responder chain. WKWebView's
    /// own paste: is private, so this shadow handles the image case and
    /// invokes the superclass implementation dynamically otherwise.
    @objc func paste(_ sender: Any?) {
        if handleImagePasteIfAvailable() { return }
        // Statically WKWebView, NOT object_getClass's superclass: the runtime
        // can interpose a dynamic subclass, which would make that lookup find
        // this very method and recurse until the stack dies.
        let sel = NSSelectorFromString("paste:")
        if let imp = class_getMethodImplementation(WKWebView.self, sel) {
            typealias PasteFunc = @convention(c) (AnyObject, Selector, Any?) -> Void
            unsafeBitCast(imp, to: PasteFunc.self)(self, sel, sender)
        }
    }
}
#endif

// MARK: - Platform-specific representable

#if os(iOS)
struct EditorWebView: UIViewRepresentable {
    let store: NoteStore
    let note: NoteFile
    let controller: EditorController
    let isNew: Bool

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(store: store, note: note, controller: controller, isNew: isNew)
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.createWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#else
struct EditorWebView: NSViewRepresentable {
    let store: NoteStore
    let note: NoteFile
    let controller: EditorController
    let isNew: Bool

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(store: store, note: note, controller: controller, isNew: isNew)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.createWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif

// MARK: - Shared coordinator

class EditorCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    /// The coordinator whose editor is currently on screen, so the macOS
    /// Edit > Undo / Redo menu commands can reach the active web view. The
    /// editor manages its own undo stack in JavaScript (it intercepts all
    /// input), so the menu has to forward into it.
    static weak var focused: EditorCoordinator?

    let store: NoteStore
    var note: NoteFile
    let controller: EditorController
    let isNew: Bool
    weak var webView: WKWebView?
    private var editorReady = false
    private var saveTimer: Timer?
    private var pendingMarkdown: String?
    /// The content last pushed into the editor, used to detect external edits.
    private var loadedContent: String?
    /// The latest known content, used to title the note on close.
    private var currentContent = ""
    private var finalized = false

    init(store: NoteStore, note: NoteFile, controller: EditorController, isNew: Bool) {
        self.store = store
        self.note = note
        self.controller = controller
        self.isNew = isNew
        super.init()
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flushPendingSave),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshFromDiskIfClean),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        #elseif os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flushPendingSave),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshFromDiskIfClean),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        #endif
    }

    deinit {
        if EditorCoordinator.focused === self { EditorCoordinator.focused = nil }
        flushPendingSave()
    }

    // MARK: Undo / Redo

    /// Forwarded from the macOS Edit menu. The web editor owns the undo stack.
    func undo() { webView?.evaluateJavaScript("undo()") }
    func redo() { webView?.evaluateJavaScript("redo()") }

    func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        userController.add(self, name: "flatnote")
        config.userContentController = userController
        config.setURLSchemeHandler(AssetSchemeHandler(baseDirectory: { [weak self] in
            self?.note.url.deletingLastPathComponent()
        }), forURLScheme: AssetSchemeHandler.scheme)

        let webView = EditorWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        controller.webView = webView
        controller.onClose = { [weak self] in self?.closeNote() }

        #if os(iOS)
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.keyboardDismissMode = .interactive
        #else
        webView.onPasteImage = { [weak self] data, mime in
            self?.attachImage(data: data, mime: mime)
        }
        #endif

        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources") ??
           Bundle.main.url(forResource: "editor", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        return webView
    }

    // MARK: WKNavigationDelegate

    /// If the web content process is ever jettisoned, reload so the editor does
    /// not silently go blank.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        editorReady = true
        EditorCoordinator.focused = self
        let content = store.readContent(of: note)
        loadedContent = content
        currentContent = content
        let escaped = Self.escapeForJS(content)
        webView.evaluateJavaScript("setContent(`\(escaped)`)")
        #if os(macOS)
        // The web view has to be the window's first responder before its
        // contenteditable can take keystrokes; SwiftUI does not do this for us.
        // Do it once the view is in a window, then focus the editor itself.
        DispatchQueue.main.async {
            webView.window?.makeFirstResponder(webView)
            webView.evaluateJavaScript("focusEditor()")
        }
        #endif
    }

    /// When the app returns to the foreground, pick up edits made to this file
    /// elsewhere (e.g. the Files app), but never overwrite unsaved in-progress
    /// edits: if there is buffered content, the user's version wins.
    @objc func refreshFromDiskIfClean() {
        guard editorReady, pendingMarkdown == nil, let webView else { return }
        let disk = store.readContent(of: note)
        guard disk != loadedContent else { return }
        loadedContent = disk
        let escaped = Self.escapeForJS(disk)
        webView.evaluateJavaScript("setContent(`\(escaped)`)")
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "flatnote",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        if action == "contentChanged", let markdown = body["markdown"] as? String {
            pendingMarkdown = markdown
            currentContent = markdown
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.flushPendingSave()
            }
        }

        if action == "pasteImage",
           let b64 = body["data"] as? String,
           let data = Data(base64Encoded: b64) {
            let mime = body["mime"] as? String ?? "image/png"
            attachImage(data: data, mime: mime)
        }

        if action == "attachImage" {
            presentImageAttachPicker()
        }

        #if os(iOS)
        if action == "sketchImage" {
            presentSketchPad()
        }
        #endif

    }

    // MARK: Attaching images

    /// Saves image bytes through the same pipeline as paste (a real file in
    /// assets/ next to the note) and hands the editor its markdown reference.
    private func attachImage(data: Data, mime: String) {
        if let rel = AssetSchemeHandler.saveImageAsset(data: data, mime: mime, noteURL: note.url) {
            webView?.evaluateJavaScript("insertPastedImage('\(rel)')")
        } else {
            store.lastError = "Could not save the image."
        }
    }

    #if os(iOS)
    /// The toolbar pencil: a finger-drawing canvas. The sketch comes back
    /// as PNG bytes and rides the same assets/ pipeline as a pasted photo,
    /// so the note stays a plain markdown file.
    private func presentSketchPad() {
        let sketch = SketchViewController()
        sketch.onDone = { [weak self] data in
            guard let data else { return }
            self?.attachImage(data: data, mime: "image/png")
        }
        let nav = UINavigationController(rootViewController: sketch)
        nav.modalPresentationStyle = .fullScreen
        var top = webView?.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(nav, animated: true)
    }

    /// The toolbar paperclip: the system photo picker, which needs no
    /// photo-library permission because it runs out of process.
    private func presentImageAttachPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        var top = webView?.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(picker, animated: true)
    }
    #elseif os(macOS)
    private func presentImageAttachPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            self.attachImage(data: data, mime: Self.mime(forExtension: url.pathExtension))
        }
    }

    private static func mime(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "webp": return "image/webp"
        default: return "image/png"
        }
    }
    #endif

    // MARK: Closing

    /// Called when the editor closes: save, then title a brand-new note from
    /// its first line, or discard it if it was never written to.
    func closeNote() {
        guard !finalized else { return }
        finalized = true
        if EditorCoordinator.focused === self { EditorCoordinator.focused = nil }
        flushPendingSave()
        guard isNew else { return }
        if currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.deleteNote(note)
        } else {
            note = store.renameToFirstLine(note, content: currentContent)
        }
    }

    // MARK: Saving

    /// Writes any pending edit to disk immediately. Safe to call repeatedly;
    /// it is a no-op when there is nothing buffered. Invoked on debounce,
    /// on app resignation, and on teardown so no edit is lost.
    @objc func flushPendingSave() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard let markdown = pendingMarkdown else { return }
        pendingMarkdown = nil
        store.saveContent(markdown, to: note)
    }

    // MARK: Helpers

    static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            // Template literals normalize CRLF/CR to LF in the cooked string;
            // escaping CR preserves the file's line endings byte-for-byte, so
            // opening a CRLF file in place never dirties or rewrites it.
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

#if os(iOS)
extension EditorCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        // Formats the asset store names correctly; anything else is written
        // as PNG-labelled data only as a last resort.
        let known = ["public.png": "image/png", "public.jpeg": "image/jpeg",
                     "com.compuserve.gif": "image/gif", "public.heic": "image/heic",
                     "org.webmproject.webp": "image/webp"]
        guard let typeId = provider.registeredTypeIdentifiers.first(where: { known[$0] != nil })
            ?? provider.registeredTypeIdentifiers.first else { return }
        provider.loadDataRepresentation(forTypeIdentifier: typeId) { [weak self] data, _ in
            guard let data else { return }
            DispatchQueue.main.async {
                self?.attachImage(data: data, mime: known[typeId] ?? "image/png")
            }
        }
    }
}

/// A deliberately plain sketch pad: one black pen, white paper, finger or
/// Pencil. Done hands back PNG bytes (nil for an empty or cancelled sketch);
/// the caller files them like any other attached image.
final class SketchViewController: UIViewController {
    private let canvas = PKCanvasView()
    var onDone: ((Data?) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sketch"
        view.backgroundColor = .systemBackground
        // Black-on-white regardless of dark mode: the sketch is destined for
        // paper-white PNG, so what you draw is exactly what the note shows.
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .white
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 6)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)),
        ]
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped)),
            UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(clearTapped)),
        ]
    }

    @objc private func cancelTapped() {
        onDone?(nil)
        dismiss(animated: true)
    }

    @objc private func clearTapped() {
        canvas.drawing = PKDrawing()
    }

    @objc private func doneTapped() {
        let drawing = canvas.drawing
        guard !drawing.bounds.isEmpty else {
            onDone?(nil)
            dismiss(animated: true)
            return
        }
        // Crop to the strokes with breathing room, flatten onto white; the
        // note gets a tight picture, not a screen-sized empty page.
        let rect = drawing.bounds.insetBy(dx: -24, dy: -24)
        let ink = drawing.image(from: rect, scale: 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let flattened = UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: rect.size))
            ink.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        onDone?(flattened.pngData())
        dismiss(animated: true)
    }
}
#endif
