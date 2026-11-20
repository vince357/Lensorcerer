import SwiftUI
import AppKit

/// Copy or move — the two tabs of the destinations panel.
enum TransferMode: String {
    case copy, move
}

/// Xee-style side panel: Copy | Move tabs, a "Choose a Destination…" button
/// and the list of folders already used. Double-clicking a folder copies or
/// moves the current file there, depending on the selected tab.
///
/// Rows are plain views (not a List) so clicking them doesn't take keyboard
/// focus away from the image: arrows, Delete, Escape… keep working.
struct DestinationsPanel: View {
    @ObservedObject var settings = AppSettings.shared
    @Binding var mode: TransferMode
    let onChooseFolder: () -> Void
    let onPerform: (URL) -> Void
    let onClose: () -> Void

    @State private var selected: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $mode) {
                    Text(L("transfer.copyTab")).tag(TransferMode.copy)
                    Text(L("transfer.moveTab")).tag(TransferMode.move)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .help(L("transfer.close"))
                .accessibilityLabel(L("transfer.close"))
            }

            Button(L("transfer.choose"), action: onChooseFolder)
                .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(settings.destinationHistory, id: \.self) { path in
                        row(for: path)
                    }
                }
            }

            if settings.destinationHistory.isEmpty {
                Text(L("transfer.emptyHistory"))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.08))
    }

    private func row(for path: String) -> some View {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let exists = FileManager.default.fileExists(atPath: path)
        let isSelected = selected == path
        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundColor(exists ? .accentColor : .gray)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(exists ? .white : .gray)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(isSelected ? Color.accentColor.opacity(0.6) : Color.clear))
        .contentShape(Rectangle())
        .help(path)
        .gesture(TapGesture(count: 2).onEnded {
            selected = path
            onPerform(url)
        }.exclusively(before: TapGesture().onEnded { selected = path }))
        .contextMenu {
            Button(L("transfer.removeFromList")) { settings.forgetDestination(path) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(path)
    }
}
