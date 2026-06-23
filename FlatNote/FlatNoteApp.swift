import SwiftUI

extension Notification.Name {
    /// Posted by the macOS File > New Note command; observed by the library view.
    static let flatNoteNewNote = Notification.Name("flatNoteNewNote")
}

@main
struct FlatNoteApp: App {
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
