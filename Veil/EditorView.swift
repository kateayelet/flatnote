import SwiftUI
import WebKit

struct EditorView: View {
    @ObservedObject var fileStore: MarkdownFileStore
    @Binding var currentFile: MarkdownFile?

    var body: some View {
        EditorWebView(fileStore: fileStore, currentFile: $currentFile)
            .ignoresSafeArea(.container, edges: .bottom)
    }
}

struct EditorWebView: UIViewRepresentable {
    @ObservedObject var fileStore: MarkdownFileStore
    @Binding var currentFile: MarkdownFile?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "veil")
        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.keyboardDismissMode = .interactive
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources") ??
           Bundle.main.url(forResource: "editor", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            // Fallback: load inline HTML so the screen is never blank
            let fallbackHTML = "<html><body><h1>Could not load editor.html</h1><p>Bundle path: \(Bundle.main.bundlePath)</p></body></html>"
            webView.loadHTMLString(fallbackHTML, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        let fileID = currentFile?.id
        if coord.loadedFileID != fileID || (fileID == nil && !coord.editorReady) {
            coord.loadedFileID = fileID
            let content = currentFile.flatMap { fileStore.readContent(of: $0) } ?? ""
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            coord.pendingContent = escaped
            if coord.editorReady {
                webView.evaluateJavaScript("setContent(`\(escaped)`)")
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EditorWebView
        weak var webView: WKWebView?
        var loadedFileID: UUID?
        var editorReady = false
        var pendingContent: String?
        private var saveTimer: Timer?

        init(_ parent: EditorWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            editorReady = true
            if let content = pendingContent {
                webView.evaluateJavaScript("setContent(`\(content)`)")
                pendingContent = nil
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                    didReceive message: WKScriptMessage) {
            guard message.name == "veil",
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            if action == "contentChanged", let markdown = body["markdown"] as? String {
                saveTimer?.invalidate()
                saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    guard let self = self, let file = self.parent.currentFile else { return }
                    self.parent.fileStore.saveContent(markdown, to: file)
                }
            }
        }
    }
}
