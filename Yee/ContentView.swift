import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var store = MediaStore()
    @ObservedObject private var settings = AppSettings.shared

    @State private var zoomScale: CGFloat = 0
    @State private var imagePixelSize: CGSize? = nil
    @State private var panOffset: CGSize = .zero
    @State private var nudgeToken: Int = 0
    @State private var nudgeDelta: CGSize = .zero
    @State private var gifPaused: Bool = false
    @State private var gifStepToken: Int = 0
    @State private var toastMessage: String? = nil
    @State private var showDeleteConfirm = false
    @State private var fileToDeletePermanently: MediaFile? = nil
    @State private var hasOpenedAnything = false
    @State private var containerSize: CGSize = .zero
    @State private var showTransferPanel = false
    @State private var transferMode: TransferMode = .copy
    @State private var pendingConflict: TransferRequest? = nil
    @State private var showConflict = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black.ignoresSafeArea()

                if store.files.isEmpty {
                    if hasOpenedAnything && store.lastOpenWasEmpty {
                        EmptyFolderView()
                    } else {
                        DropZoneView()
                    }
                } else {
                    ImageDisplayView(store: store,
                                      zoomScale: $zoomScale,
                                      imagePixelSize: $imagePixelSize,
                                      panOffset: $panOffset,
                                      gifPaused: $gifPaused,
                                      containerSize: $containerSize,
                                      stepRequestToken: gifStepToken,
                                      nudgeToken: nudgeToken,
                                      nudgeDelta: nudgeDelta)
                }

                VStack {
                    Spacer()
                    StatusBarView(store: store,
                                  imagePixelSize: imagePixelSize,
                                  displayedZoomPercent: Int(round(currentZoomValue() * 100)))
                }

                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.callout)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(10)
                            .padding(.bottom, settings.showStatusBar ? 40 : 16)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showTransferPanel {
                DestinationsPanel(mode: $transferMode,
                                  onChooseFolder: chooseDestination,
                                  onPerform: { transferCurrent(to: $0) },
                                  onClose: closeTransferPanel)
                    .onExitCommand(perform: closeTransferPanel)
            }
        }
        .background(KeyCatcher(actions: keyActions))
        .onAppear {
            if let w = NSApp.keyWindow ?? NSApp.mainWindow, w.identifier == nil {
                w.identifier = AppDelegate.mainWindowID
            }
            consumePendingURLIfNeeded()
            for attempt in 1...6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.3) {
                    consumePendingURLIfNeeded()
                    AppDelegate.enforceSingleWindowIfNeeded()
                }
            }
        }
        .onChange(of: store.currentIndex) { _ in
            if settings.alwaysFitOnOpen { zoomScale = 0 }
            panOffset = .zero
            gifPaused = false
            updateWindowTitle()
        }
        .onChange(of: store.currentFolderURL) { _ in updateWindowTitle() }
        .onReceive(NotificationCenter.default.publisher(for: .openURL)) { notif in
            if let url = notif.object as? URL { open(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .yeeMenuAction)) { notif in
            if let action = notif.object as? YeeMenuAction { handle(action) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .yeeSortChanged)) { _ in
            store.reload()
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .alert(L("alert.deletePermanentTitle"), isPresented: $showDeleteConfirm,
               presenting: fileToDeletePermanently) { file in
            Button(L("alert.cancel"), role: .cancel) {}
            Button(L("alert.deletePermanent"), role: .destructive) {
                store.delete(file, permanently: true) { _, msg in showToast(msg) }
            }
        } message: { file in
            Text(L("alert.deletePermanentMessage", file.name))
        }
        .alert(L("conflict.title"), isPresented: $showConflict, presenting: pendingConflict) { req in
            Button(L("conflict.replace"), role: .destructive) {
                runTransfer(req, to: store.destinationURL(for: req.file, in: req.folder), replacing: true)
            }
            Button(L("conflict.keepBoth")) {
                runTransfer(req, to: store.uniqueURL(for: req.file, in: req.folder), replacing: false)
            }
            Button(L("alert.cancel"), role: .cancel) { focusViewer() }
        } message: { req in
            Text(L("conflict.message", req.file.name, req.folder.lastPathComponent))
        }
        .onChange(of: transferMode) { _ in focusViewer() }
    }

    private func updateWindowTitle() {
        DispatchQueue.main.async { NSApp.mainWindow?.title = store.currentFile?.name ?? "Yee" }
    }

    /// Single entry point for opening a file or a folder, whatever the
    /// source (Finder/Dock, cold launch, drag & drop, Open panel).
    private func open(_ url: URL) {
        AppDelegate.pendingURL = nil
        hasOpenedAnything = true
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { store.openFolder(url: url) } else { store.openFile(url: url) }
        zoomScale = 0; panOffset = .zero
        updateWindowTitle()
    }

    private func consumePendingURLIfNeeded() {
        if let url = AppDelegate.pendingURL { open(url) }
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { toastMessage = nil } }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { open(url) }
        }
        return true
    }

    private func handle(_ action: YeeMenuAction) {
        switch action {
        case .openFile: presentOpenPanel()
        case .revealInFinder: store.revealInFinder()
        case .moveToTrash: moveCurrentToTrash()
        case .deletePermanently: askPermanentDelete()
        case .copyTo: openTransferPanel(.copy)
        case .moveTo: openTransferPanel(.move)
        case .rotateCW: store.rotateCW()
        case .zoomIn: setZoom(currentZoomValue() + 0.25)
        case .zoomOut: setZoom(currentZoomValue() - 0.25)
        case .zoomReset: setZoom(1.0)
        case .fitOnScreen: zoomScale = 0; panOffset = .zero
        case .toggleFullScreen: NSApp.mainWindow?.toggleFullScreen(nil)
        case .nextFile: store.goNext()
        case .previousFile: store.goPrevious()
        case .firstFile: store.goFirst()
        case .lastFile: store.goLast()
        case .randomFile: store.goRandom()
        case .backFromRandom: store.goBackFromRandom()
        }
    }

    // MARK: - Copy to / Move to

    private func openTransferPanel(_ mode: TransferMode) {
        transferMode = mode
        withAnimation(.easeOut(duration: 0.15)) { showTransferPanel = true }
    }

    private func closeTransferPanel() {
        withAnimation(.easeOut(duration: 0.15)) { showTransferPanel = false }
        focusViewer()
    }

    /// "Choose a Destination…": pick a folder, then copy/move right away.
    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("transfer.choosePrompt")
        if panel.runModal() == .OK, let url = panel.url { transferCurrent(to: url) }
        focusViewer()
    }

    /// Copies or moves the current file to `folder` (per the selected tab),
    /// asking first if a file with the same name is already there.
    private func transferCurrent(to folder: URL) {
        defer { focusViewer() }
        guard let file = store.currentFile else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            showToast(L("transfer.missingFolder", folder.lastPathComponent)); return
        }
        if folder.standardizedFileURL.path == file.url.deletingLastPathComponent().standardizedFileURL.path {
            showToast(L("transfer.sameFolder")); return
        }
        settings.rememberDestination(folder)
        let req = TransferRequest(file: file, folder: folder, mode: transferMode)
        let target = store.destinationURL(for: file, in: folder)
        if FileManager.default.fileExists(atPath: target.path) {
            pendingConflict = req
            showConflict = true
        } else {
            runTransfer(req, to: target, replacing: false)
        }
    }

    private func runTransfer(_ req: TransferRequest, to target: URL, replacing: Bool) {
        store.transfer(req.file, to: target, mode: req.mode, replacing: replacing) { _, msg in showToast(msg) }
        focusViewer()
    }

    /// Gives keyboard focus back to the image (arrows, Delete, Escape…)
    /// after interacting with the panel.
    private func focusViewer() {
        NotificationCenter.default.post(name: .yeeFocusViewer, object: nil)
    }

    private func moveCurrentToTrash() {
        guard let file = store.currentFile else { return }
        store.delete(file, permanently: false) { _, msg in showToast(msg) }
    }

    private func askPermanentDelete() {
        guard let file = store.currentFile else { return }
        fileToDeletePermanently = file
        showDeleteConfirm = true
    }

    /// Scale currently shown on screen — the manual zoom, or the real fit
    /// scale when in auto-fit mode — so zooming from a fitted image starts
    /// from what the user actually sees instead of jumping from 100%.
    private func currentZoomValue() -> CGFloat {
        ImageDisplayView.effectiveScale(zoomScale: zoomScale, natural: imagePixelSize,
                                        containerSize: containerSize,
                                        rotationDegrees: store.pendingRotation,
                                        settings: settings)
    }
    private func setZoom(_ value: CGFloat) { zoomScale = max(0.05, min(20, value)) }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    // MARK: - Low-level keyboard: arrows (pan/nav), space (GIF), enter (resume),
    // delete, and symbol-based zoom keys (character-matched, so it works
    // correctly on AZERTY and with the numeric keypad — the previous
    // hardware-keyCode approach didn't account for ISO/French key layouts).
    private var keyActions: KeyActionSet {
        KeyActionSet(
            onZoomIn: { fine in setZoom(currentZoomValue() + (fine ? 0.1 : 0.25)) },
            onZoomOut: { fine in setZoom(currentZoomValue() - (fine ? 0.1 : 0.25)) },
            onZoomReset: { zoomScale = 1.0 },
            onFitResetKey: { zoomScale = 0; panOffset = .zero },
            onSpace: {
                if !gifPaused { gifPaused = true } else { gifStepToken += 1 }
            },
            onEnter: {
                if gifPaused { gifPaused = false }
            },
            onArrow: { direction in
                if isZoomedBeyond() {
                    let delta: CGFloat = 30
                    switch direction {
                    case .left:  nudgeDelta = CGSize(width: delta, height: 0)
                    case .right: nudgeDelta = CGSize(width: -delta, height: 0)
                    case .up:    nudgeDelta = CGSize(width: 0, height: delta)
                    case .down:  nudgeDelta = CGSize(width: 0, height: -delta)
                    }
                    nudgeToken += 1
                } else {
                    switch direction {
                    case .left:  store.goPrevious()
                    case .right: store.goNext()
                    default: break
                    }
                }
            },
            onDelete: { permanently in
                if permanently { askPermanentDelete() } else { moveCurrentToTrash() }
            },
            onToggleFullScreen: { handle(.toggleFullScreen) },
            onEscape: { if showTransferPanel { closeTransferPanel() } }
        )
    }

    /// Arrows pan only when a manual zoom makes the image overflow the
    /// window; otherwise they navigate. (Previously `zoomScale > 1.0`, which
    /// no longer works now that zooming starts from the fit scale: an image
    /// zoomed from 37% to 62% can overflow the window while staying < 100%.)
    private func isZoomedBeyond() -> Bool {
        guard zoomScale > 0, let nat = imagePixelSize else { return false }
        let n = ImageDisplayView.rotatedSize(nat, rotationDegrees: store.pendingRotation)
        return n.width * zoomScale > containerSize.width + 0.5
            || n.height * zoomScale > containerSize.height + 0.5
    }
}

// MARK: - Drop zone (nothing opened yet)
struct DropZoneView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64)).foregroundColor(.gray)
            Text(L("dropzone.title")).font(.title2).foregroundColor(.gray)
            Text(L("dropzone.subtitle"))
                .font(.caption).foregroundColor(.gray.opacity(0.7))
        }
    }
}

// MARK: - Empty folder (opened, but no supported media)
struct EmptyFolderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 64)).foregroundColor(.gray)
            Text(L("dropzone.empty.title")).font(.title2).foregroundColor(.gray)
            Text(L("dropzone.empty.subtitle"))
                .font(.caption).foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }
}

// MARK: - Key action bundle
enum ArrowDirection { case left, right, up, down }

struct KeyActionSet {
    let onZoomIn: (Bool) -> Void
    let onZoomOut: (Bool) -> Void
    let onZoomReset: () -> Void
    let onFitResetKey: () -> Void
    let onSpace: () -> Void
    let onEnter: () -> Void
    let onArrow: (ArrowDirection) -> Void
    let onDelete: (Bool) -> Void          // true = permanent (Shift held)
    let onToggleFullScreen: () -> Void
    let onEscape: () -> Void
}

/// A copy/move waiting for the user's answer about a name conflict.
struct TransferRequest {
    let file: MediaFile
    let folder: URL
    let mode: TransferMode
}

struct KeyCatcher: NSViewRepresentable {
    let actions: KeyActionSet
    func makeNSView(context: Context) -> KeyCatcherNSView {
        let v = KeyCatcherNSView(); v.actions = actions; return v
    }
    func updateNSView(_ nsView: KeyCatcherNSView, context: Context) { nsView.actions = actions }
}

class KeyCatcherNSView: NSView {
    var actions: KeyActionSet?

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NotificationCenter.default.removeObserver(self, name: .yeeFocusViewer, object: nil)
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(takeFocus),
                                                   name: .yeeFocusViewer, object: nil)
        }
    }

    @objc private func takeFocus() {
        guard let w = window, w.isKeyWindow || w.isMainWindow else { return }
        w.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let a = actions else { return }
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)

        // ⌘F: full screen. Matched by character so it follows the layout.
        // (The View menu shows macOS's own full-screen item, ⌃⌘F.)
        if cmd, event.charactersIgnoringModifiers?.lowercased() == "f" {
            a.onToggleFullScreen(); return
        }

        if !cmd {
            // Symbol keys matched by resolved character (layout + numpad safe)
            if let chars = event.characters {
                if chars == "+" || chars == "=" { a.onZoomIn(shift); return }
                if chars == "-" { a.onZoomOut(shift); return }
                if chars == "_" { a.onZoomOut(true); return }
                if chars == "*" { a.onFitResetKey(); return }
            }
        }

        switch event.keyCode {
        case 29: if !cmd { a.onZoomReset(); return }          // '0' (digit row)
        case 82: if !cmd { a.onZoomReset(); return }          // numpad 0
        case 49: a.onSpace(); return                          // space
        case 36: a.onEnter(); return                          // return/enter
        case 123: a.onArrow(.left); return
        case 124: a.onArrow(.right); return
        case 126: a.onArrow(.up); return
        case 125: a.onArrow(.down); return
        case 51, 117: a.onDelete(shift); return               // ⌫ / ⌦ ; Shift = permanent
        case 53: a.onEscape(); return                          // escape
        default:
            super.keyDown(with: event)
        }
    }
}
