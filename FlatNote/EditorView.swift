import SwiftUI
import WebKit
#if canImport(UIKit)
import UIKit
#endif

struct EditorView: View {
    let store: NoteStore
    let note: NoteFile

    var body: some View {
        EditorWebView(store: store, note: note)
            #if os(iOS)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(note.displayName)
    }
}

// MARK: - Platform-specific representable

#if os(iOS)
struct EditorWebView: UIViewRepresentable {
    let store: NoteStore
    let note: NoteFile

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(store: store, note: note)
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

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(store: store, note: note)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.createWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif

// MARK: - Shared coordinator

class EditorCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let store: NoteStore
    let note: NoteFile
    weak var webView: WKWebView?
    private var editorReady = false
    private var saveTimer: Timer?
    private var pendingMarkdown: String?
    /// The content last pushed into the editor, used to detect external edits.
    private var loadedContent: String?

    init(store: NoteStore, note: NoteFile) {
        self.store = store
        self.note = note
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
        #endif
    }

    deinit {
        flushPendingSave()
    }

    func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        userController.add(self, name: "flatnote")
        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        #if os(iOS)
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.keyboardDismissMode = .interactive
        #endif

        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources") ??
           Bundle.main.url(forResource: "editor", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        return webView
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        editorReady = true
        let content = store.readContent(of: note)
        loadedContent = content
        let escaped = Self.escapeForJS(content)
        webView.evaluateJavaScript("setContent(`\(escaped)`)")
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
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.flushPendingSave()
            }
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

    private static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
