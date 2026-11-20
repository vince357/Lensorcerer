import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            HStack {
                Text(L("prefs.language"))
                    .font(.headline)
                    .frame(width: 120, alignment: .leading)
                Picker("", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
                Spacer()
            }

            sectionBlock(L("prefs.section.opening")) {
                Toggle(L("prefs.openFullScreen"), isOn: $settings.openFullScreenByDefault)
                Toggle(L("prefs.alwaysFit"), isOn: $settings.alwaysFitOnOpen)
                Toggle(L("prefs.includeSubfolders"), isOn: $settings.includeSubfolders)
                Toggle(L("prefs.singleWindow"), isOn: $settings.singleWindowMode)
            }

            sectionBlock(L("prefs.section.interface")) {
                Toggle(L("prefs.showStatusBar"), isOn: $settings.showStatusBar)
            }

            sectionBlock(L("prefs.section.fitting")) {
                Toggle(L("menu.shrinkH"), isOn: $settings.shrinkHorizontal)
                Toggle(L("menu.shrinkV"), isOn: $settings.shrinkVertical)
                Toggle(L("menu.stretchH"), isOn: $settings.stretchHorizontal)
                Toggle(L("menu.stretchV"), isOn: $settings.stretchVertical)
            }
        }
        .padding(24)
        .frame(width: 440)
        // Settings save themselves (see AppSettings); only the language
        // change needs extra work here.
        .onChange(of: settings.language) { newValue in
            UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            promptRestartIfNeeded()
        }
    }

    /// A section with its bold title on the LEFT and its controls stacked on
    /// the RIGHT — matching the language row's layout, per feedback (not a
    /// title-above-content block).
    @ViewBuilder
    private func sectionBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.headline)
                .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            Spacer()
        }
    }

    private func promptRestartIfNeeded() {
        let alert = NSAlert()
        alert.messageText = L("prefs.restartTitle")
        alert.informativeText = L("prefs.restartMessage")
        alert.addButton(withTitle: L("prefs.restartLater"))
        alert.alertStyle = .informational
        alert.runModal()
    }
}
