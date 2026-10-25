import Foundation

/// Wo ChemJournal seine Daten ablegt.
///
/// - **Lokal:** Journal wie bisher unter `~/Documents/ChemJournalData.json`; Versionsverlauf, Backups und
///   CAS-Datenbank unter `~/Library/Application Support/ChemJournal/`.
/// - **iCloud Drive:** alles zusammen in `iCloud Drive/ChemJournal/`. macOS synchronisiert den Ordner selbst;
///   dafür braucht die App weder CloudKit noch einen Apple-Developer-Account.
nonisolated enum StorageMode: String, CaseIterable, Sendable {
    case local
    case iCloud

    var title: String {
        switch self {
        case .local: "Nur auf diesem Mac"
        case .iCloud: "iCloud Drive"
        }
    }

    private static let defaultsKey = "storageMode"

    static var current: StorageMode {
        get { StorageMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .local }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

nonisolated struct AppPaths: Sendable, Equatable {
    /// Ordner mit `ChemJournalData.json` und `ChemJournalData.bak.json`.
    let dataDirectory: URL
    /// Ordner mit `Versionen/`, `Backups/` und `CAS-Datenbank.json`.
    let supportDirectory: URL

    var journalFile: URL { dataDirectory.appendingPathComponent("ChemJournalData.json") }
    var versionsDirectory: URL { supportDirectory.appendingPathComponent("Versionen", isDirectory: true) }
    var backupsDirectory: URL { supportDirectory.appendingPathComponent("Backups", isDirectory: true) }
    var casDatabaseFile: URL { supportDirectory.appendingPathComponent("CAS-Datenbank.json") }

    /// `~/Library/Mobile Documents/com~apple~CloudDocs` – existiert nur, wenn iCloud Drive eingeschaltet ist.
    static var iCloudDriveRoot: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }

    static var isICloudAvailable: Bool { iCloudDriveRoot != nil }

    static func forMode(_ mode: StorageMode) -> AppPaths {
        let fm = FileManager.default
        switch mode {
        case .iCloud:
            if let root = iCloudDriveRoot {
                let dir = root.appendingPathComponent("ChemJournal", isDirectory: true)
                return AppPaths(dataDirectory: dir, supportDirectory: dir)
            }
            return forMode(.local)   // iCloud Drive aus → lokal weiterarbeiten statt Daten zu verlieren
        case .local:
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ChemJournal", isDirectory: true)
            return AppPaths(dataDirectory: documents, supportDirectory: support)
        }
    }

    static var current: AppPaths { forMode(StorageMode.current) }

    /// Legt die Ordner an (Fehler werden beim Schreiben gemeldet).
    func createDirectories() {
        let fm = FileManager.default
        for dir in [dataDirectory, supportDirectory, versionsDirectory, backupsDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
