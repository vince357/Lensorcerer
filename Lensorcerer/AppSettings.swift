import Foundation
import Combine

enum SortKey: String, CaseIterable, Identifiable {
    case name, dateModified, size, fileType
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: return L("sort.name")
        case .dateModified: return L("sort.dateModified")
        case .size: return L("sort.size")
        case .fileType: return L("sort.fileType")
        }
    }
}

enum SortDirection: String {
    case ascending, descending
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private init() { load() }

    /// Set while `load()` runs, so the property observers below don't write
    /// half-loaded values back to UserDefaults.
    private var isLoading = false

    /// Every setting saves itself when it changes; the ones that affect the
    /// file list also ask the open window to reload it.
    private func changed(reloadList: Bool = false) {
        guard !isLoading else { return }
        save()
        if reloadList { NotificationCenter.default.post(name: .sortChanged, object: nil) }
    }

    @Published var language: AppLanguage = .english { didSet { changed() } }

    @Published var openFullScreenByDefault: Bool = false { didSet { changed() } }
    @Published var alwaysFitOnOpen: Bool = true { didSet { changed() } }
    @Published var singleWindowMode: Bool = true { didSet { changed() } }

    @Published var shrinkHorizontal: Bool  = true { didSet { changed() } }
    @Published var shrinkVertical: Bool    = true { didSet { changed() } }
    @Published var stretchHorizontal: Bool = false { didSet { changed() } }
    @Published var stretchVertical: Bool   = false { didSet { changed() } }

    @Published var showStatusBar: Bool = true { didSet { changed() } }

    @Published var sortKey: SortKey         = .name { didSet { changed(reloadList: true) } }
    @Published var sortDirection: SortDirection = .ascending { didSet { changed(reloadList: true) } }
    @Published var includeSubfolders: Bool  = false { didSet { changed(reloadList: true) } }

    /// Folders used with Copy to / Move to, most recent first.
    @Published var destinationHistory: [String] = [] { didSet { changed() } }
    static let maxDestinations = 10

    /// Puts `folder` at the top of the history (once), capped at maxDestinations.
    func rememberDestination(_ folder: URL) {
        var list = destinationHistory.filter { $0 != folder.path }
        list.insert(folder.path, at: 0)
        destinationHistory = Array(list.prefix(Self.maxDestinations))
    }

    func forgetDestination(_ path: String) {
        destinationHistory.removeAll { $0 == path }
    }

    private let defaults = UserDefaults.standard

    /// The app was called Yee (bundle id com.vince357.Yee) before being
    /// renamed Lensorcerer. On first launch under the new identifier, copy
    /// the settings saved under the old one so nothing is lost.
    private func migrateFromFormerIdentifierIfNeeded() {
        let flag = "migratedFromYee"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        guard let old = UserDefaults(suiteName: "com.vince357.Yee") else { return }
        let keys = ["language", "openFullScreen", "alwaysFit", "singleWindow",
                    "shrinkH", "shrinkV", "stretchH", "stretchV", "statusBar",
                    "subfolders", "sortKey", "sortDir", "destinations", "AppleLanguages"]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    func load() {
        migrateFromFormerIdentifierIfNeeded()
        isLoading = true
        defer { isLoading = false }
        if let raw = defaults.string(forKey: "language"), let l = AppLanguage(rawValue: raw) {
            language = l
        } else {
            // Default to English regardless of system locale, per product decision.
            language = .english
        }
        openFullScreenByDefault = defaults.bool(forKey: "openFullScreen")
        alwaysFitOnOpen         = defaults.object(forKey: "alwaysFit") as? Bool ?? true
        singleWindowMode        = defaults.object(forKey: "singleWindow") as? Bool ?? true
        shrinkHorizontal        = defaults.object(forKey: "shrinkH") as? Bool ?? true
        shrinkVertical          = defaults.object(forKey: "shrinkV") as? Bool ?? true
        stretchHorizontal       = defaults.bool(forKey: "stretchH")
        stretchVertical         = defaults.bool(forKey: "stretchV")
        showStatusBar           = defaults.object(forKey: "statusBar") as? Bool ?? true
        includeSubfolders       = defaults.bool(forKey: "subfolders")
        if let raw = defaults.string(forKey: "sortKey"), let k = SortKey(rawValue: raw) { sortKey = k }
        if let raw = defaults.string(forKey: "sortDir"), let d = SortDirection(rawValue: raw) { sortDirection = d }
        destinationHistory      = defaults.stringArray(forKey: "destinations") ?? []
    }

    func save() {
        defaults.set(language.rawValue,       forKey: "language")
        defaults.set(openFullScreenByDefault, forKey: "openFullScreen")
        defaults.set(alwaysFitOnOpen,         forKey: "alwaysFit")
        defaults.set(singleWindowMode,        forKey: "singleWindow")
        defaults.set(shrinkHorizontal,        forKey: "shrinkH")
        defaults.set(shrinkVertical,          forKey: "shrinkV")
        defaults.set(stretchHorizontal,       forKey: "stretchH")
        defaults.set(stretchVertical,         forKey: "stretchV")
        defaults.set(showStatusBar,           forKey: "statusBar")
        defaults.set(includeSubfolders,       forKey: "subfolders")
        defaults.set(sortKey.rawValue,        forKey: "sortKey")
        defaults.set(sortDirection.rawValue,  forKey: "sortDir")
        defaults.set(destinationHistory,      forKey: "destinations")
    }
}
