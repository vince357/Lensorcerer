import SwiftUI
import AppKit

enum MenuAction {
    case openFile
    case revealInFinder
    case moveToTrash
    case deletePermanently
    case copyTo, moveTo
    case rotateCW
    case zoomIn, zoomOut, zoomReset, fitOnScreen
    case toggleFullScreen
    case nextFile, previousFile, firstFile, lastFile
    case randomFile, backFromRandom
}

struct LensorcererCommands: Commands {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {

        CommandGroup(replacing: .appInfo) {
            Button(L("about.title")) { showAboutPanel() }
        }

        CommandGroup(replacing: .help) {
            Button(L("menu.help")) { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button(L("menu.open")) { post(.openFile) }
                .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button(L("menu.revealInFinder")) { post(.revealInFinder) }
                .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button(L("menu.rotate")) { post(.rotateCW) }
                .keyboardShortcut("r", modifiers: .command)

            Divider()

            // Open the destinations panel on the matching tab.
            Button(L("menu.copyTo")) { post(.copyTo) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(L("menu.moveTo")) { post(.moveTo) }
                .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            // ⌫: straight to the Trash (recoverable, so no confirmation).
            // ⇧⌫: permanent delete, always confirmed.
            Button(L("menu.delete")) { post(.moveToTrash) }
                .keyboardShortcut(.delete, modifiers: [])
            Button(L("menu.deletePermanently")) { post(.deletePermanently) }
                .keyboardShortcut(.delete, modifiers: .shift)
        }

        // Our items go into the system-provided View menu ("Présentation" in
        // French) instead of a CommandMenu of our own: a separate CommandMenu
        // produced a second "View"/"Affichage" menu next to the system one.
        // Replacing the .toolbar group also drops "Show/Customize Toolbar",
        // which made no sense here (Lensorcerer has no toolbar).
        // No full-screen item of our own: macOS already adds its standard
        // "Enter/Exit Full Screen" (⌃⌘F) to this menu; ⌘F is still handled
        // by KeyCatcher in ContentView.
        CommandGroup(replacing: .toolbar) {
            // Symbol shortcuts use `localization: .custom`: by default SwiftUI
            // remaps them to the US physical key, so on AZERTY the menu showed
            // "8" for * and "à" for 0. The keys themselves are also handled by
            // KeyCatcher (character-based), so they work on every layout.
            Button(L("menu.fitOnScreen")) { post(.fitOnScreen) }
                .keyboardShortcut("*", modifiers: [], localization: .custom)
            Button(L("menu.zoom100")) { post(.zoomReset) }
                .keyboardShortcut("0", modifiers: [], localization: .custom)
            Button(L("menu.zoomIn")) { post(.zoomIn) }
                .keyboardShortcut("=", modifiers: [], localization: .custom)
            Button(L("menu.zoomOut")) { post(.zoomOut) }
                .keyboardShortcut("-", modifiers: [], localization: .custom)

            Divider()

            Menu(L("menu.fitOptions")) {
                Toggle(L("menu.shrinkH"), isOn: $settings.shrinkHorizontal)
                Toggle(L("menu.shrinkV"), isOn: $settings.shrinkVertical)
                Divider()
                Toggle(L("menu.stretchH"), isOn: $settings.stretchHorizontal)
                Toggle(L("menu.stretchV"), isOn: $settings.stretchVertical)
            }
            Toggle(L("menu.alwaysFit"), isOn: $settings.alwaysFitOnOpen)

            Divider()

            Toggle(L("menu.showStatusBar"), isOn: $settings.showStatusBar)

            Divider()

            // Sort key and direction as native checkable items (Toggle), so the
            // menu shows the system checkmark on the active choice. Previously
            // the direction was a single item with a "✓" baked into its label.
            Menu(L("menu.sortBy")) {
                ForEach(SortKey.allCases) { key in
                    Toggle(key.label, isOn: Binding(
                        get: { settings.sortKey == key },
                        set: { if $0 { settings.sortKey = key } }))
                }
                Divider()
                Toggle(L("menu.sortAscending"), isOn: Binding(
                    get: { settings.sortDirection == .ascending },
                    set: { if $0 { settings.sortDirection = .ascending } }))
                Toggle(L("menu.sortDescending"), isOn: Binding(
                    get: { settings.sortDirection == .descending },
                    set: { if $0 { settings.sortDirection = .descending } }))
            }

            Toggle(L("menu.includeSubfolders"), isOn: $settings.includeSubfolders)
        }

        CommandMenu(L("menu.navigation")) {
            Button(L("menu.next")) { post(.nextFile) }
                .keyboardShortcut(.pageDown, modifiers: [])
            Button(L("menu.previous")) { post(.previousFile) }
                .keyboardShortcut(.pageUp, modifiers: [])
            Divider()
            Button(L("menu.first")) { post(.firstFile) }
                .keyboardShortcut(.home, modifiers: [])
            Button(L("menu.last")) { post(.lastFile) }
                .keyboardShortcut(.end, modifiers: [])
            Divider()
            Button(L("menu.random")) { post(.randomFile) }
                .keyboardShortcut("r", modifiers: [])
            Button(L("menu.backFromRandom")) { post(.backFromRandom) }
                .keyboardShortcut("r", modifiers: .shift)
        }
    }

    private func post(_ action: MenuAction) {
        NotificationCenter.default.post(name: .menuAction, object: action)
    }

    private func showAboutPanel() {
        let credits = NSMutableAttributedString(string: L("about.tagline") + "\n\n" + L("about.license") + "\n")
        let linkRange: NSRange
        let linkText = L("about.github")
        let full = NSMutableAttributedString(attributedString: credits)
        full.append(NSAttributedString(string: "\n"))
        let linkStart = full.length
        full.append(NSAttributedString(string: linkText))
        // NSString length (UTF-16), not Swift's character count, so the range
        // stays correct with accented or other non-ASCII characters.
        linkRange = NSRange(location: linkStart, length: (linkText as NSString).length)
        full.addAttribute(.link, value: "https://github.com/vince357/Lensorcerer", range: linkRange)
        full.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: full.length))

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: full,
            NSApplication.AboutPanelOptionKey(rawValue: "ApplicationName"): "Lensorcerer",
            .applicationVersion: version
        ])
    }
}
