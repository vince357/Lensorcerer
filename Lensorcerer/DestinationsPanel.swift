import SwiftUI
import AppKit
import ImageIO

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
    /// Selected folder path; kept across files so Return reuses it.
    @Binding var selected: String?
    let onChooseFolder: () -> Void
    let onPerform: (URL) -> Void
    let onClose: () -> Void

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
            Button(L("transfer.removeFromList")) {
                settings.forgetDestination(path)
                if selected == path { selected = settings.destinationHistory.first }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(path)
    }
}

// MARK: - Name conflict

/// A copy/move waiting for the user's answer about a name conflict.
struct TransferRequest: Identifiable {
    let id = UUID()
    let file: MediaFile
    let folder: URL
    let mode: TransferMode
    var existingURL: URL { folder.appendingPathComponent(file.name) }
}

/// What to do when the destination already has a file with the same name.
enum ConflictChoice { case overwrite, skip, duplicate }

/// Shows both versions side by side (preview, dimensions, size, date) and
/// lets the user overwrite, skip or duplicate.
struct ConflictView: View {
    let request: TransferRequest
    let onChoose: (ConflictChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("conflict.title")).font(.headline)
            Text(L("conflict.message", request.file.name, request.folder.lastPathComponent))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 20) {
                FileSummaryView(title: L(request.mode == .copy ? "conflict.toCopy" : "conflict.toMove"),
                                url: request.file.url)
                FileSummaryView(title: L("conflict.existing"), url: request.existingURL)
            }

            HStack {
                Button(L("conflict.skip"), role: .cancel) { onChoose(.skip) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("conflict.duplicate")) { onChoose(.duplicate) }
                    .keyboardShortcut(.defaultAction)
                Button(L("conflict.overwrite"), role: .destructive) { onChoose(.overwrite) }
            }
            Text(L("conflict.overwriteNote"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// Preview + dimensions, size and modification date of one file.
private struct FileSummaryView: View {
    let title: String
    let url: URL
    @State private var thumbnail: NSImage? = nil
    @State private var pixelSize: CGSize? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.85))
                if let img = thumbnail {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(4)
                } else {
                    Image(systemName: "doc").font(.system(size: 32)).foregroundColor(.gray)
                }
            }
            .frame(width: 230, height: 160)
            infoLine(L("conflict.dimensions"),
                     pixelSize.map { "\(Int($0.width)) × \(Int($0.height)) px" } ?? "—")
            infoLine(L("conflict.size"), sizeText)
            infoLine(L("conflict.modified"), dateText)
        }
        .frame(width: 230, alignment: .leading)
        .onAppear(perform: load)
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private var values: URLResourceValues? {
        try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    }
    private var sizeText: String { values?.fileSize.map(formatFileSize) ?? "—" }
    private var dateText: String {
        guard let d = values?.contentModificationDate else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: AppSettings.shared.language.rawValue)
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    /// Small thumbnail and pixel size via ImageIO (fast, no full decode).
    private func load() {
        let u = url
        DispatchQueue.global(qos: .userInitiated).async {
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return }
            var size: CGSize? = nil
            if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyPixelWidth] as? Int,
               let h = props[kCGImagePropertyPixelHeight] as? Int {
                size = CGSize(width: w, height: h)
            }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 480
            ]
            let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
                .map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async {
                pixelSize = size
                thumbnail = thumb
            }
        }
    }
}
