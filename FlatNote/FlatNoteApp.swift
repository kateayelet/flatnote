import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var macAppDelegate
    #endif

    init() {
        #if os(macOS)
        // A document-based Mac app shows the "open a file" panel on launch by
        // default (the Finder-looking window). Turn that off so FlatNote opens
        // a fresh untitled note instead — you land in a blank note ready to type.
        UserDefaults.standard.register(
            defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false]
        )
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // Every note opens as a real document, edited in place wherever the
        // file lives — the library folder, iCloud Drive, or any folder the
        // user picks. One window per note; File > New / Open / Open Recent /
        // Save As / Rename / Duplicate / Move To / Revert and the Window menu
        // all come from the system document machinery. Declared first so a
        // fresh launch opens an untitled note, ready to type — the app is an
        // editor before it is a shelf.
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentEditorView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 900, height: 900)
        // Centered document title above the toolbar row, Typora-style; the
        // unified style crams the title against the traffic lights instead.
        .windowToolbarStyle(.expanded)
        .commands {
            FlatNoteEditorCommands()
        }

        // The library shelf: browse, search, and manage the iCloud notes.
        // A single Window scene, so macOS lists it in the Window menu and
        // reopens it from there after it is closed. No quit-on-close delegate
        // anymore: with a stock document File menu the app can never be
        // stranded windowless (App Review Guideline 4).
        Window("FlatNote Library", id: "library") {
            NoteLibraryView()
                // Tag the NSWindow so Open Library can find it and bring it
                // in front of the note that was already key.
                .background(LibraryWindowHost())
        }
        .defaultSize(width: 900, height: 640)
        // Attached here rather than on DocumentGroup: SwiftUI silently
        // ignores .appInfo replacements on the document scene.
        .commands {
            AboutCommands()
        }
        #else
        WindowGroup {
            NoteLibraryView()
        }
        #endif
    }
}

#if os(macOS)
/// Retargets the stock App menu About item. SwiftUI `CommandGroup(replacing:
/// .appInfo)` is silently dropped on the document scene (see
/// `FlatNoteEditorCommands`); the system About panel would otherwise appear
/// instead of `AboutView`.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        rewireAboutMenu()
        // SwiftUI finishes building the menu on the next turn.
        DispatchQueue.main.async { [weak self] in
            self?.rewireAboutMenu()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        rewireAboutMenu()
    }

    private func rewireAboutMenu() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let item = aboutMenuItem(in: appMenu) else { return }
        item.target = self
        item.action = #selector(showAbout(_:))
    }

    private func aboutMenuItem(in menu: NSMenu) -> NSMenuItem? {
        let stock = #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        let ours = #selector(showAbout(_:))
        if let item = menu.items.first(where: { $0.action == stock || $0.action == ours }) {
            return item
        }
        return menu.items.first { $0.title.hasPrefix("About ") }
    }

    @objc func showAbout(_ sender: Any?) {
        AboutWindow.show()
    }
}

/// The "What is FlatNote?" card as a real About window: same `AboutView` as
/// Settings → Philosophy and the iOS quick action, content-hugging, dismissed
/// by the window chrome. Created from AppKit so it does not depend on
/// SwiftUI `openWindow` or the DocumentGroup command table.
enum AboutWindow {
    static let title = "What is FlatNote?"

    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: AboutView())
        hosting.sizingOptions = [.intrinsicContentSize]
        let panel = NSWindow(contentViewController: hosting)
        panel.title = title
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        size(panel, to: hosting)
        panel.center()
        window = panel
        panel.makeKeyAndOrderFront(nil)
        // SwiftUI's first fitting pass can land before the card has a height.
        DispatchQueue.main.async { size(panel, to: hosting) }
    }

    private static func size(_ panel: NSWindow, to hosting: NSHostingController<AboutView>) {
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        panel.setContentSize(size)
    }
}

/// Same Credits card as Settings → Philosophy, as a real window.
enum CreditsWindow {
    static let title = "Credits"

    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: CreditsView())
        hosting.sizingOptions = [.intrinsicContentSize]
        let panel = NSWindow(contentViewController: hosting)
        panel.title = title
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        size(panel, to: hosting)
        panel.center()
        window = panel
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { size(panel, to: hosting) }
    }

    private static func size(_ panel: NSWindow, to hosting: NSHostingController<CreditsView>) {
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        panel.setContentSize(size)
    }
}

/// Replaces the stock About panel with the same AboutView used everywhere
/// else. Lives on the library `Window` scene because DocumentGroup drops
/// `.appInfo` replacements.
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About FlatNote") {
                AboutWindow.show()
            }
        }
        CommandGroup(after: .appInfo) {
            Button("Credits") {
                CreditsWindow.show()
            }
        }
    }
}

/// The tile library is a separate window. SwiftUI's `openWindow` will create
/// or unhide it, but when a document note is already key it often stays
/// behind that note. Tag the window and order it front ourselves.
enum LibraryWindow {
    static let id = "library"

    static func open(_ openWindow: OpenWindowAction) {
        openWindow(id: id)
        bringToFront()
        // First open: the window may not exist until the next turn.
        DispatchQueue.main.async { bringToFront() }
    }

    static func bringToFront() {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == id || $0.title == "FlatNote Library"
        }) else { return }
        window.makeKeyAndOrderFront(nil)
    }
}

/// Zero-size view whose only job is to stamp the library NSWindow with a
/// stable identifier the first time it attaches.
private struct LibraryWindowHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { Self.apply(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.tag(nsView) }
    }

    private static func tag(_ view: NSView) {
        view.window?.identifier = NSUserInterfaceItemIdentifier(LibraryWindow.id)
    }

    private static func apply(_ view: NSView) {
        tag(view)
        view.window?.makeKeyAndOrderFront(nil)
    }
}

/// Edit > Undo / Redo forwarded into the key window's web editor, which owns
/// the undo stack (it intercepts all input, so WebKit's native undo is empty).
struct FlatNoteEditorCommands: Commands {
    @FocusedValue(\.activeEditor) private var editor: EditorController?
    @AppStorage("flatnoteOutlineVisible") private var outlineVisible = true
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // NOTE (2026-07-21): this DocumentGroup scene honors File/Edit-area
        // CommandGroups only. Replacing `.appInfo` or Help here is silently
        // ignored, and a second Commands struct in the same @CommandsBuilder
        // is dropped. About lives on the library Window (AboutCommands) and
        // MacAppDelegate retargets the stock App menu item as a fallback.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { editor?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(editor == nil)
            Button("Redo") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editor == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Open Library") { LibraryWindow.open(openWindow) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        CommandGroup(after: .importExport) {
            Button("Export as PDF…") { editor?.exportPDF() }
                .disabled(editor == nil)
        }
        CommandGroup(after: .sidebar) {
            Toggle("Outline", isOn: $outlineVisible)
                .keyboardShortcut("1", modifiers: [.command, .control])
        }

        // The Paragraph and Format menus, sized to the markdown FlatNote
        // actually renders: no tables, math, or footnotes it cannot show.
        CommandMenu("Paragraph") {
            Group {
            Button("Heading 1") { editor?.format("h1") }
                .keyboardShortcut("1", modifiers: .command)
            Button("Heading 2") { editor?.format("h2") }
                .keyboardShortcut("2", modifiers: .command)
            Button("Heading 3") { editor?.format("h3") }
                .keyboardShortcut("3", modifiers: .command)
            Button("Heading 4") { editor?.format("h4") }
                .keyboardShortcut("4", modifiers: .command)
            Button("Heading 5") { editor?.format("h5") }
                .keyboardShortcut("5", modifiers: .command)
            Button("Heading 6") { editor?.format("h6") }
                .keyboardShortcut("6", modifiers: .command)
            Button("Paragraph") { editor?.format("paragraph") }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Quote") { editor?.format("quote") }
                .keyboardShortcut("q", modifiers: [.command, .option])
            Button("Callout") { editor?.format("callout") }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Divider()
            Button("Bullet List") { editor?.format("bullet") }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button("Numbered List") { editor?.format("ordered") }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Button("Checklist") { editor?.format("task") }
                .keyboardShortcut("x", modifiers: [.command, .option])
            }
            .disabled(editor == nil)
        }

        CommandMenu("Format") {
            Group {
            Button("Bold") { editor?.format("bold") }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { editor?.format("italic") }
                .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") { editor?.format("strike") }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button("Code") { editor?.format("code") }
                .keyboardShortcut("`", modifiers: .control)
            Divider()
            Button("Link") { editor?.format("link") }
                .keyboardShortcut("k", modifiers: .command)
            Button("Image…") { editor?.format("attach") }
            }
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
