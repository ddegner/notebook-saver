import AppIntents

struct NotebookSaverShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(intent: ProcessPhotoIntent(),
                        phrases: ["Process photo in \(.applicationName)", "Extract text with \(.applicationName)"]),
        ]
    }
}