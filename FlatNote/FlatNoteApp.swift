import SwiftUI

extension Notification.Name {
    /// Posted when the user asks "What is FlatNote?" from the Home Screen
    /// quick action; the library presents the About sheet.
    static let flatnoteShowAbout = Notification.Name("flatnoteShowAbout")
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set when the app cold-launches from the quick action; consumed by the
    /// library once the UI exists (the notification would fire before anyone
    /// is listening).
    static var pendingShortcutType: String?

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            Self.pendingShortcutType = item.type
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "com.aftrveil.flatnote.about" {
            NotificationCenter.default.post(name: .flatnoteShowAbout, object: nil)
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}
#endif

@main
struct FlatNoteApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        // The library shelf: browse, search, and manage the iCloud notes.
        // A single Window scene, so macOS lists it in the Window menu and
        // reopens it from there after it is closed. No quit-on-close delegate
        // anymore: with a stock document File menu the app can never be
        // stranded windowless (App Review Guideline 4).
        Window("FlatNote", id: "library") {
            NoteLibraryView()
        }
        .defaultSize(width: 900, height: 640)


        // Every note opens as a real document, edited in place wherever the
        // file lives — the library folder, iCloud Drive, or any folder the
        // user picks. One window per note; File > New / Open / Open Recent /
        // Save As / Rename / Duplicate / Move To / Revert and the Window menu
        // all come from the system document machinery.
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentEditorView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 760, height: 880)
        .commands {
            FlatNoteEditorCommands()
        }
        #else
        WindowGroup {
            NoteLibraryView()
        }
        #endif
    }
}

#if os(macOS)
/// Edit > Undo / Redo forwarded into the key window's web editor, which owns
/// the undo stack (it intercepts all input, so WebKit's native undo is empty).
struct FlatNoteEditorCommands: Commands {
    @FocusedValue(\.activeEditor) private var editor: EditorController?

    var body: some Commands {
        // NOTE (2026-07-21): SwiftUI here honors File/Edit-area CommandGroups
        // only. Replacing or inserting in the app menu (.appInfo) and Help is
        // silently ignored, and a second Commands struct in the same
        // @CommandsBuilder block is dropped. The What-is-FlatNote card is
        // reachable on Mac via Settings > Philosophy instead.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { editor?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(editor == nil)
            Button("Redo") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editor == nil)
        }
        CommandGroup(after: .importExport) {
            Button("Export as PDF…") { editor?.exportPDF() }
                .disabled(editor == nil)
        }
        CommandGroup(replacing: .printItem) {
            // Replacing .printItem also removes the stock Page Setup, so
            // provide both.
            Button("Page Setup…") { _ = NSPageLayout().runModal(with: NSPrintInfo.shared) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Print…") { editor?.printNote() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(editor == nil)
        }
    }
}
#endif
