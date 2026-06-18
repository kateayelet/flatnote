import SwiftUI
import WebKit
#if canImport(UIKit)
import UIKit
#endif

/// Bridges the SwiftUI find bar to the editor's web view.
@Observable
final class EditorController {
    weak var webView: WKWebView?
    var matchCount = 0
    var currentMatch = 0

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
}

struct EditorView: View {
    let store: NoteStore
    let note: NoteFile

    @State private var controller = EditorController()
    @State private var showingFind = false
    @State private var findText = ""

    var body: some View {
        EditorWebView(store: store, note: note, controller: controller)
            #if os(iOS)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(note.displayName)
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
                #endif
            }
            .safeAreaInset(edge: .top) {
                if showingFind {
                    findBar
                }
            }
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
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
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
#endif

// MARK: - Platform-specific representable

#if os(iOS)
struct EditorWebView: UIViewRepresentable {
    let store: NoteStore
    let note: NoteFile
    let controller: EditorController

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(store: store, note: note, controller: controller)
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

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(store: store, note: note, controller: controller)
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
    let controller: EditorController
    weak var webView: WKWebView?
    private var editorReady = false
    private var saveTimer: Timer?
    private var pendingMarkdown: String?
    /// The content last pushed into the editor, used to detect external edits.
    private var loadedContent: String?

    init(store: NoteStore, note: NoteFile, controller: EditorController) {
        self.store = store
        self.note = note
        self.controller = controller
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

        #if os(iOS)
        let webView = EditorWKWebView(frame: .zero, configuration: config)
        #else
        let webView = WKWebView(frame: .zero, configuration: config)
        #endif
        webView.navigationDelegate = self
        self.webView = webView
        controller.webView = webView

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

    static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
