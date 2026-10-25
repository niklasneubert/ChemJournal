import CryptoKit
import Foundation

/// Gespeicherter Stand eines Ansatzes.
nonisolated struct VersionSnapshot: Codable, Sendable {
    var date: Date
    var reason: String
    var projectID: UUID?
    var projectTitle: String?
    var experiment: Experiment
}

/// Eintrag in der Versionsliste (ohne den eigentlichen Inhalt, damit die Liste schnell lädt).
nonisolated struct VersionInfo: Codable, Sendable, Hashable, Identifiable {
    var file: String
    var experimentID: UUID
    var date: Date
    var reason: String
    var title: String
    var projectTitle: String?
    var stageCount: Int
    var chemicalCount: Int
    var hash: String
    /// Wird beim Ausdünnen nie entfernt (vor dem Löschen / vor dem Wiederherstellen).
    var pinned: Bool

    var id: String { "\(experimentID.uuidString)/\(file)" }
}

nonisolated struct BackupInfo: Sendable, Hashable, Identifiable {
    var url: URL
    var date: Date
    var size: Int64
    var id: URL { url }
}

/// Versionsverlauf pro Ansatz und tägliche Backups des ganzen Journals.
///
/// Ordnerstruktur (unter `AppPaths.supportDirectory`):
/// ```
/// Versionen/<Ansatz-UUID>/index.json
/// Versionen/<Ansatz-UUID>/2026-10-23T14-05-00Z.json
/// Backups/ChemJournal-2026-10-23.json
/// ```
/// Nicht thread-sicher für sich: wird ausschließlich auf der seriellen Queue von `JournalPersistence` benutzt.
nonisolated final class JournalHistory: @unchecked Sendable {
    let versionsDirectory: URL
    let backupsDirectory: URL
    /// Mindestabstand zwischen zwei automatischen Versionen desselben Ansatzes.
    let minimumInterval: TimeInterval

    /// Zuletzt gespeicherter Stand je Ansatz (Stand der Datei auf der Platte).
    private var lastSeen: [UUID: Experiment] = [:]
    private var indexCache: [UUID: [VersionInfo]] = [:]

    init(versionsDirectory: URL, backupsDirectory: URL, minimumInterval: TimeInterval = 600) {
        self.versionsDirectory = versionsDirectory
        self.backupsDirectory = backupsDirectory
        self.minimumInterval = minimumInterval
    }

    // MARK: Versionen anlegen

    /// Stand nach dem Laden der Datei merken – Grundlage für die erste Version nach dem Start.
    func seed(_ projects: [Project]) {
        lastSeen = Dictionary(projects.flatMap(\.experiments).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Nach jedem Speichern aufgerufen.
    ///
    /// Eine Version ist der Stand, der *vor* einer neuen Bearbeitung bestand: Ist seit der letzten Version eines Ansatzes
    /// mindestens `minimumInterval` vergangen, wird der zuletzt gespeicherte Stand gesichert (falls er noch nicht im
    /// Verlauf ist). So geht auch ein Zwischenstand vor einer längeren Pause nicht verloren.
    /// - Parameter force: beim Beenden/Umzug – den aktuellen Stand jedes geänderten Ansatzes sofort sichern.
    func recordChanges(_ projects: [Project], now: Date = Date(), force: Bool = false) {
        for project in projects {
            for experiment in project.experiments {
                let previous = lastSeen[experiment.id]
                if let previous, previous == experiment, !force { continue }
                lastSeen[experiment.id] = experiment
                let index = loadIndex(experiment.id)

                if index.isEmpty || force {
                    guard let data = encode(experiment) else { continue }
                    let hash = Self.hash(data)
                    if index.first?.hash == hash { continue }
                    write(experiment, hash: hash, project: project, reason: index.isEmpty ? "Erste Sicherung" : "Beim Beenden", pinned: false, now: now)
                    continue
                }
                guard let newest = index.first, now.timeIntervalSince(newest.date) >= minimumInterval,
                      let previous, let data = encode(previous) else { continue }
                let hash = Self.hash(data)
                if hash != newest.hash {
                    write(previous, hash: hash, project: project, reason: "Automatisch", pinned: false, now: now)
                }
            }
        }
    }

    /// Sofort sichern, z. B. vor dem Löschen oder vor dem Wiederherstellen einer älteren Version.
    func snapshot(_ experiment: Experiment, project: Project?, reason: String, pinned: Bool, now: Date = Date()) {
        guard let data = encode(experiment) else { return }
        let hash = Self.hash(data)
        // Gleicher Inhalt schon als neueste Version vorhanden → nur markieren
        var index = loadIndex(experiment.id)
        if let first = index.first, first.hash == hash {
            if pinned && !first.pinned {
                index[0].pinned = true
                index[0].reason = reason
                saveIndex(index, for: experiment.id)
            }
            return
        }
        write(experiment, hash: hash, project: project, reason: reason, pinned: pinned, now: now)
    }

    private func write(_ experiment: Experiment, hash: String, project: Project?, reason: String, pinned: Bool, now: Date) {
        let dir = directory(for: experiment.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = Self.fileName(for: now)
        let snapshot = VersionSnapshot(date: now, reason: reason, projectID: project?.id, projectTitle: project?.title, experiment: experiment)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let full = try? encoder.encode(snapshot) else { return }
        do { try full.write(to: dir.appendingPathComponent(file), options: .atomic) }
        catch { print("Versionsverlauf: Schreiben fehlgeschlagen: \(error)"); return }
        let info = VersionInfo(file: file, experimentID: experiment.id, date: now, reason: reason,
                               title: experiment.title, projectTitle: project?.title,
                               stageCount: experiment.stages.count, chemicalCount: experiment.stages.reduce(0) { $0 + $1.chemicals.count },
                               hash: hash, pinned: pinned)
        var index = loadIndex(experiment.id).filter { $0.file != file }
        index.insert(info, at: 0)
        index = prune(index, now: now, in: dir)
        saveIndex(index, for: experiment.id)
    }

    // MARK: Ausdünnen

    /// < 24 h: alles; bis 30 Tage: neueste pro Tag; danach neueste pro Woche; markierte immer; höchstens 300.
    private func prune(_ index: [VersionInfo], now: Date, in dir: URL) -> [VersionInfo] {
        var keep: [VersionInfo] = []
        var seenBuckets = Set<String>()
        let calendar = Calendar(identifier: .iso8601)
        for info in index.sorted(by: { $0.date > $1.date }) {
            let age = now.timeIntervalSince(info.date)
            var bucket: String?
            if age >= 30 * 86_400 {
                let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: info.date)
                bucket = "w\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
            } else if age >= 86_400 {
                let c = calendar.dateComponents([.year, .month, .day], from: info.date)
                bucket = "d\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
            }
            if info.pinned || bucket == nil || seenBuckets.insert(bucket!).inserted {
                keep.append(info)
            }
        }
        if keep.count > 300 {
            let unpinned = keep.filter { !$0.pinned }
            let dropCount = keep.count - 300
            let drop = Set(unpinned.suffix(dropCount).map(\.file))
            keep.removeAll { drop.contains($0.file) }
        }
        let kept = Set(keep.map(\.file))
        for info in index where !kept.contains(info.file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(info.file))
        }
        return keep
    }

    // MARK: Lesen

    func versions(for experimentID: UUID) -> [VersionInfo] { loadIndex(experimentID) }

    func loadSnapshot(_ info: VersionInfo) -> VersionSnapshot? {
        let url = directory(for: info.experimentID).appendingPathComponent(info.file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VersionSnapshot.self, from: data)
    }

    /// Neueste Version jedes Ansatzes, den es im Journal nicht mehr gibt (gelöschte Ansätze).
    func deletedExperiments(existing: Set<UUID>) -> [VersionInfo] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: versionsDirectory, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir -> VersionInfo? in
            guard let id = UUID(uuidString: dir.lastPathComponent), !existing.contains(id) else { return nil }
            return loadIndex(id).first
        }.sorted { $0.date > $1.date }
    }

    /// Gelöschten Ansatz endgültig aus dem Verlauf entfernen.
    func removeHistory(for experimentID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: experimentID))
        indexCache[experimentID] = nil
    }

    // MARK: Tägliche Backups

    /// Kopiert die Journal-Datei einmal pro Tag nach `Backups/`.
    @discardableResult
    func dailyBackup(of journalFile: URL, now: Date = Date()) -> URL? {
        let target = backupsDirectory.appendingPathComponent("ChemJournal-\(Self.dayString(now)).json")
        guard !FileManager.default.fileExists(atPath: target.path) else { return nil }
        return backup(journalFile, to: target, now: now)
    }

    /// Sofort-Backup (Einstellungen › „Jetzt sichern“).
    @discardableResult
    func manualBackup(of journalFile: URL, now: Date = Date()) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        return backup(journalFile, to: backupsDirectory.appendingPathComponent("ChemJournal-manuell-\(stamp).json"), now: now)
    }

    private func backup(_ journalFile: URL, to target: URL, now: Date) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: journalFile.path) else { return nil }
        try? fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        do { try fm.copyItem(at: journalFile, to: target) } catch { return nil }
        pruneBackups(now: now)
        return target
    }

    func backups() -> [BackupInfo] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return BackupInfo(url: url, date: values?.contentModificationDate ?? .distantPast, size: Int64(values?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }

    /// Tägliche Backups: letzte 30 Tage + je eines pro Monat für 12 Monate. Manuelle bleiben.
    private func pruneBackups(now: Date) {
        let daily = backups().filter { $0.url.lastPathComponent.range(of: #"^ChemJournal-\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil }
        var keptMonths = Set<String>()
        for (i, b) in daily.enumerated() {
            let age = now.timeIntervalSince(b.date)
            if i < 30 { continue }
            let month = String(b.url.lastPathComponent.dropFirst("ChemJournal-".count).prefix(7))
            if age < 366 * 86_400 && keptMonths.insert(month).inserted { continue }
            try? FileManager.default.removeItem(at: b.url)
        }
    }

    // MARK: intern

    private func directory(for id: UUID) -> URL { versionsDirectory.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func loadIndex(_ id: UUID) -> [VersionInfo] {
        if let cached = indexCache[id] { return cached }
        let url = directory(for: id).appendingPathComponent("index.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([VersionInfo].self, from: $0) } ?? []
        let sorted = list.sorted { $0.date > $1.date }
        indexCache[id] = sorted
        return sorted
    }

    private func saveIndex(_ index: [VersionInfo], for id: UUID) {
        indexCache[id] = index
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: directory(for: id).appendingPathComponent("index.json"), options: .atomic)
    }

    /// Andere Macs (iCloud) können Versionen hinzufügen – Zwischenspeicher verwerfen.
    func invalidateCaches() {
        indexCache.removeAll()
    }

    private func encode(_ experiment: Experiment) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(experiment)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func fileName(for date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date).replacingOccurrences(of: ":", with: "-") + ".json"
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
