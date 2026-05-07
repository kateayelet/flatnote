import SwiftUI
import WebKit

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

    init(store: NoteStore, note: NoteFile) {
        self.store = store
        self.note = note
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
        let escaped = Self.escapeForJS(content)
        webView.evaluateJavaScript("setContent(`\(escaped)`)")
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "flatnote",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        if action == "contentChanged", let markdown = body["markdown"] as? String {
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.store.saveContent(markdown, to: self.note)
            }
        }
    }

    // MARK: Helpers

    private static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
