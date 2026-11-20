import SwiftUI
import AppKit

@main
struct LensorcererApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, minHeight: 300)
        }
        .commands {
            LensorcererCommands()
        }

        // Preferences window
        Settings {
            PreferencesView()
        }

        // Help window
        Window(L("help.windowTitle"), id: "help") {
            HelpView()
        }
    }
}
