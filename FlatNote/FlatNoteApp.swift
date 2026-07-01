import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    /// Posted by the macOS File > New Note command; observed by the library view.
    static let flatNoteNewNote = Notification.Name("flatNoteNewNote")
}

#if os(macOS)
/// FlatNote is a single-window library on the Mac. Once "New Window" is replaced
/// by "New Note" there is no command left to recreate the window, so closing it
/// would strand the app running with no way back. Quit instead: notes autosave
/// to disk, so nothing is lost. (App Review Guideline 4.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

@main
struct FlatNoteApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            NoteLibraryView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 640)
        .commands {
            // Replace the stock "New" item so Cmd+N creates a note.
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .flatNoteNewNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        #endif
    }
}
