import Foundation
import Observation

/// Gemeinsamer Datenbestand für alle Fenster.
///
/// - Speichert 0.8 s nach der letzten Änderung; beim Beenden sofort.
/// - Legt dabei automatisch Versionen je Ansatz und ein tägliches Backup an (`JournalHistory`).
/// - Speicherort lokal oder in iCloud Drive (`StorageMode`). Im iCloud-Modus wird regelmäßig geprüft, ob ein anderer
///   Mac die Datei geändert hat; ohne eigene ungespeicherte Änderungen wird der neue Stand übernommen.
@Observable
final class JournalStore {
    var projects: [Project] = [] {
        didSet {
            guard isLoaded && !isApplyingExternalChange else { return }
            if !isRestoringUndo { recordUndo(oldValue) }
            isDirty = true
            scheduleSave()
        }
    }
    /// Meldung für den Nutzer, z. B. wenn die Datei beschädigt war und aus dem Backup geladen wurde.
    var loadMessage: String?
    private(set) var isLoaded = false
    private(set) var storageMode: StorageMode
    private(set) var paths: AppPaths
    /// Zeitpunkt, zu dem zuletzt Änderungen eines anderen Macs übernommen wurden (für die Anzeige).
    private(set) var lastExternalReload: Date?

    @ObservationIgnored private var persistence: JournalPersistence?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var didStartLoading = false
    @ObservationIgnored private var isApplyingExternalChange = false
    @ObservationIgnored private var watchTimer: Timer?
    // Widerrufen (⌘Z): frühere Stände des ganzen Journals
    @ObservationIgnored private var undoStack: [[Project]] = []
    @ObservationIgnored private var redoStack: [[Project]] = []
    @ObservationIgnored private var isRestoringUndo = false
    @ObservationIgnored private var lastEditTime = Date.distantPast
    @ObservationIgnored private var lastChangeWasStructural = false
    /// Höchstzahl gemerkter Schritte.
    static let undoLimit = 100
    /// Änderungen innerhalb dieser Zeit (z. B. ein getipptes Wort) sind ein Schritt.
    static let undoGrouping: TimeInterval = 1.0
    /// Ungespeicherte Änderungen vorhanden. Verhindert, dass ein bloßes Öffnen und Schließen die Dateien neu schreibt.
    @ObservationIgnored private(set) var isDirty = false

    /// - Parameter inMemory: Für Tests – liest und schreibt keine Dateien.
    init(inMemory: Bool = JournalStore.isRunningTests) {
        let mode = inMemory ? .local : StorageMode.current
        storageMode = mode
        paths = AppPaths.forMode(mode)
        persistence = inMemory ? nil : JournalPersistence(paths: paths)
        if inMemory { isLoaded = true }
    }

    /// Für Tests: Journal mit eigenem Speicherort (z. B. ein temporärer Ordner).
    init(paths: AppPaths, mode: StorageMode = .local) {
        storageMode = mode
        self.paths = paths
        persistence = JournalPersistence(paths: paths)
    }

    static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil || env["XCTestSessionIdentifier"] != nil
    }

    // MARK: Laden & Speichern

    /// Lädt einmalig beim ersten Fenster. Die Datei wird im Hintergrund gelesen und dekodiert.
    func loadIfNeeded() async {
        guard !didStartLoading, let persistence else { return }
        didStartLoading = true
        apply(await persistence.load())
        isLoaded = true
        startWatchingIfNeeded()
    }

    private func apply(_ result: JournalPersistence.LoadResult) {
        switch result {
        case .empty:
            break
        case .loaded(let p):
            projects = p
        case .recoveredFromBackup(let p, let preserved):
            projects = p
            loadMessage = String(localized: "Die Datendatei war beschädigt. Der letzte Stand aus dem Backup wurde geladen. Die beschädigte Datei liegt unter \(preserved.lastPathComponent).")
        case .failed(let preserved):
            loadMessage = String(localized: "Die Datendatei konnte nicht gelesen werden und wurde unter \(preserved?.lastPathComponent ?? "–") gesichert. ChemJournal startet mit einem leeren Journal.")
        }
    }

    /// Speichert 0.8 s nach der letzten Änderung (Tippen löst nicht bei jedem Zeichen einen Schreibvorgang aus).
    func scheduleSave() {
        guard let persistence else { return }
        saveTask?.cancel()
        let snapshot = projects
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            persistence.save(snapshot)
            self.isDirty = false
        }
    }

    /// Sofort speichern (⌘S).
    func saveNow() {
        guard isLoaded, let persistence else { return }
        saveTask?.cancel()
        persistence.save(projects)
        isDirty = false
    }

    /// Beim Beenden: wartet, bis alle Schreibvorgänge durch sind; jede noch nicht gesicherte Änderung wird zur Version.
    func saveBeforeTermination() {
        guard isLoaded, let persistence else { return }
        saveTask?.cancel()
        persistence.saveAndWait(projects, forceVersions: true)
        isDirty = false
        CASDatabase.shared.waitForPendingWrites()
    }

    /// Für Tests: wartet auf alle Schreibvorgänge.
    func waitForPendingWrites() {
        saveTask?.cancel()
        if isDirty { persistence?.saveAndWait(projects); isDirty = false }
        persistence?.waitForPendingWrites()
    }

    // MARK: Widerrufen & Wiederholen

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Merkt den Stand vor einer Änderung. Schnell aufeinanderfolgende Tipp-Änderungen werden zu einem Schritt
    /// zusammengefasst; Hinzufügen/Löschen (Zeilen, Stufen, Ansätze, Bilder) ist immer ein eigener Schritt.
    private func recordUndo(_ old: [Project]) {
        let now = Date()
        let gap = now.timeIntervalSince(lastEditTime)
        let structural = Self.structure(old) != Self.structure(projects)
        // Nach Hinzufügen/Löschen gehören nur automatische Folgeänderungen (< 0.3 s, z. B. Neuberechnung) noch dazu;
        // danach Getipptes ist ein eigener Schritt.
        if structural || gap > Self.undoGrouping || (lastChangeWasStructural && gap > 0.3) {
            undoStack.append(old)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        }
        lastEditTime = now
        lastChangeWasStructural = structural
        redoStack.removeAll()
    }

    /// `false`, wenn es nichts zu widerrufen gibt.
    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(projects)
        restoreUndoState(previous)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(projects)
        restoreUndoState(next)
        return true
    }

    private func restoreUndoState(_ state: [Project]) {
        isRestoringUndo = true
        projects = state
        isRestoringUndo = false
        lastEditTime = .distantPast   // nächste Änderung beginnt einen neuen Schritt
    }

    private func clearUndo() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastEditTime = .distantPast
    }

    /// Anzahl der Projekte, Ansätze, Stufen, Zeilen, Analysen und Bilder – ändert sich nur beim Hinzufügen/Löschen.
    private static func structure(_ projects: [Project]) -> [Int] {
        var s = [projects.count]
        for p in projects {
            s.append(p.experiments.count)
            for e in p.experiments {
                s.append(e.stages.count)
                for st in e.stages {
                    s.append(st.chemicals.count)
                    s.append(st.yieldProducts.count)
                    s.append(st.analyses.count)
                    s.append(st.analysisFiles.count)
                    s.append(st.reactionImageData == nil ? 0 : 1)
                }
            }
        }
        return s
    }

    // MARK: Versionsverlauf

    func versions(for experimentID: UUID) async -> [VersionInfo] {
        await persistence?.versions(for: experimentID) ?? []
    }

    func snapshot(of info: VersionInfo) async -> VersionSnapshot? {
        await persistence?.loadSnapshot(info)
    }

    /// Ansätze, die gelöscht wurden, von denen es aber noch Versionen gibt (neueste Version je Ansatz).
    func deletedExperiments() async -> [VersionInfo] {
        let existing = Set(projects.flatMap(\.experiments).map(\.id))
        return await persistence?.deletedExperiments(existing: existing) ?? []
    }

    /// Vor dem Löschen sichern, damit der Ansatz wiederhergestellt werden kann.
    func recordBeforeDeletion(_ experiment: Experiment, in project: Project) {
        persistence?.snapshot(experiment, project: project, reason: "Vor dem Löschen", pinned: true)
    }

    /// Stellt eine Version wieder her und gibt die ID des wiederhergestellten Ansatzes zurück.
    /// - Parameter asCopy: `true` = als neuer Ansatz neben dem aktuellen; `false` = aktuellen Stand ersetzen
    ///   (der aktuelle Stand wird vorher selbst als Version gesichert).
    @discardableResult
    func restore(_ info: VersionInfo, asCopy: Bool) async -> UUID? {
        guard let snap = await snapshot(of: info) else { return nil }
        return restore(snap, asCopy: asCopy)
    }

    @discardableResult
    func restore(_ snap: VersionSnapshot, asCopy: Bool) -> UUID {
        var experiment = snap.experiment
        if asCopy {
            let stamp = snap.date.appFormatted(date: .abbreviated, time: .shortened)
            experiment.id = UUID()
            experiment.title += String(localized: " (Version vom \(stamp))")
            experiment.stages = experiment.stages.map { var s = $0; s.id = UUID(); return s }
            experiment.updatedAt = Date()
            insert(experiment, preferredProject: snap.projectID, projectTitle: snap.projectTitle)
            return experiment.id
        }
        if let p = projects.firstIndex(where: { $0.experiments.contains { $0.id == experiment.id } }),
           let e = projects[p].experiments.firstIndex(where: { $0.id == experiment.id }) {
            persistence?.snapshot(projects[p].experiments[e], project: projects[p], reason: "Vor dem Wiederherstellen", pinned: true)
            experiment.updatedAt = Date()
            projects[p].experiments[e] = experiment
        } else {
            // Gelöschter Ansatz: wieder einfügen
            insert(experiment, preferredProject: snap.projectID, projectTitle: snap.projectTitle)
        }
        return experiment.id
    }

    private func insert(_ experiment: Experiment, preferredProject: UUID?, projectTitle: String?) {
        if let id = preferredProject, let p = projects.firstIndex(where: { $0.id == id }) {
            projects[p].experiments.append(experiment)
            projects[p].isExpanded = true
        } else if let title = projectTitle, let p = projects.firstIndex(where: { $0.title == title }) {
            projects[p].experiments.append(experiment)
            projects[p].isExpanded = true
        } else {
            projects.append(Project(title: projectTitle ?? String(localized: "Wiederhergestellt"), experiments: [experiment]))
        }
    }

    /// Gelöschten Ansatz endgültig aus dem Verlauf entfernen.
    func purgeHistory(for experimentID: UUID) async {
        await persistence?.removeHistory(for: experimentID)
    }

    // MARK: Backups

    func backups() async -> [BackupInfo] { await persistence?.backups() ?? [] }

    /// Speichert und legt sofort ein Backup an.
    func backupNow() async -> URL? {
        guard isLoaded, let persistence else { return nil }
        saveTask?.cancel()
        persistence.save(projects)
        isDirty = false
        return await persistence.manualBackup()
    }

    enum BackupRestoreResult: Equatable {
        /// Zurückgespielt; der vorherige Stand liegt als Backup unter `safetyBackup`.
        case restored(safetyBackup: URL?)
        case unreadable
    }

    /// Spielt ein Backup des ganzen Journals zurück. Der aktuelle Stand wird vorher gespeichert, jede Änderung als
    /// Version gesichert und zusätzlich als Backup abgelegt; außerdem lässt sich das Zurückspielen mit ⌘Z widerrufen.
    func restoreBackup(_ backup: BackupInfo) async -> BackupRestoreResult {
        guard isLoaded, let persistence else { return .unreadable }
        guard let restored = await persistence.loadBackup(backup.url) else { return .unreadable }
        saveTask?.cancel()
        persistence.saveAndWait(projects, forceVersions: true)
        isDirty = false
        let safety = await persistence.safetyBackup()
        lastEditTime = .distantPast   // eigener Widerrufen-Schritt
        projects = restored
        saveNow()
        return .restored(safetyBackup: safety)
    }

    // MARK: Speicherort

    enum SwitchCheck: Equatable {
        case ready
        /// Am Ziel liegt schon ein Journal (z. B. von einem anderen Mac).
        case targetHasJournal(experiments: Int, modified: Date?)
        case unavailable
    }

    func checkSwitch(to mode: StorageMode) async -> SwitchCheck {
        if mode == .iCloud && !AppPaths.isICloudAvailable { return .unavailable }
        return await checkSwitch(to: AppPaths.forMode(mode))
    }

    func checkSwitch(to target: AppPaths) async -> SwitchCheck {
        guard target != paths else { return .ready }
        let probe = JournalPersistence(paths: target)
        switch await probe.load() {
        case .loaded(let p), .recoveredFromBackup(let p, _):
            let modified = (try? target.journalFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return .targetHasJournal(experiments: p.reduce(0) { $0 + $1.experiments.count }, modified: modified)
        case .empty, .failed:
            return .ready
        }
    }

    func switchStorage(to mode: StorageMode, useExistingJournal: Bool) async {
        await switchStorage(to: AppPaths.forMode(mode), mode: mode, useExistingJournal: useExistingJournal,
                            casDatabase: CASDatabase.shared)
    }

    /// Zieht Journal, Versionen, Backups und CAS-Datenbank an den neuen Speicherort um.
    /// - Parameter useExistingJournal: Liegt am Ziel schon ein Journal: `true` = dieses verwenden (das bisherige wird dort
    ///   als Backup abgelegt), `false` = mit dem bisherigen überschreiben (das vorhandene wird vorher gesichert).
    ///   Am alten Ort bleibt alles liegen – nichts wird gelöscht.
    func switchStorage(to target: AppPaths, mode: StorageMode, useExistingJournal: Bool, casDatabase: CASDatabase?) async {
        guard let old = persistence else { return }
        guard target != paths else { StorageMode.current = mode; storageMode = mode; return }
        saveTask?.cancel()
        old.saveAndWait(projects, forceVersions: true)
        isDirty = false
        stopWatching()

        let source = paths
        target.createDirectories()
        await Task.detached {
            Self.mergeDirectory(from: source.versionsDirectory, to: target.versionsDirectory)
            Self.mergeDirectory(from: source.backupsDirectory, to: target.backupsDirectory)
        }.value
        casDatabase?.relocate(to: target.casDatabaseFile)

        let new = JournalPersistence(paths: target)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fm = FileManager.default
        if useExistingJournal, case .loaded(let p) = await new.load() {
            // Bisheriges Journal als Backup am Ziel aufbewahren
            try? fm.copyItem(at: source.journalFile, to: target.backupsDirectory.appendingPathComponent("ChemJournal-vor-Umzug-\(stamp).json"))
            isApplyingExternalChange = true
            projects = p
            isApplyingExternalChange = false
            clearUndo()
        } else {
            if fm.fileExists(atPath: target.journalFile.path) {
                try? fm.copyItem(at: target.journalFile, to: target.backupsDirectory.appendingPathComponent("ChemJournal-ersetzt-\(stamp).json"))
            }
            _ = await new.load()   // Zustand der Ziel-Datei kennenlernen (Backup-Rotation)
            new.saveAndWait(projects)
        }
        persistence = new
        paths = target
        storageMode = mode
        if casDatabase === CASDatabase.shared { StorageMode.current = mode }
        startWatchingIfNeeded()
    }

    /// Kopiert Dateien, die am Ziel noch fehlen (rekursiv). Vorhandene werden nicht überschrieben.
    nonisolated private static func mergeDirectory(from source: URL, to target: URL) {
        let fm = FileManager.default
        let base = source.standardizedFileURL.path
        guard let items = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in items {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            let relative = String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            let dest = target.appendingPathComponent(relative)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else if !fm.fileExists(atPath: dest.path) {
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: url, to: dest)
            }
        }
    }

    // MARK: Änderungen anderer Macs (iCloud)

    private func startWatchingIfNeeded() {
        stopWatching()
        guard storageMode == .iCloud, persistence != nil else { return }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkForExternalChanges() }
        }
    }

    private func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
    }

    /// Prüft, ob ein anderer Mac die Datei geändert hat (alle 5 s und beim Aktivieren der App).
    func checkForExternalChanges() async {
        guard storageMode == .iCloud, isLoaded, !isDirty, let persistence else { return }
        guard let result = await persistence.reloadIfChangedExternally() else { return }
        guard !isDirty else { return }   // während des Ladens wurde getippt → eigener Stand gewinnt
        isApplyingExternalChange = true
        apply(result)
        isApplyingExternalChange = false
        clearUndo()
        lastExternalReload = Date()
        CASDatabase.shared.reloadFromDisk()
    }
}

/// Liest und schreibt `ChemJournalData.json` auf einer seriellen Queue.
/// Die Reihenfolge der Schreibvorgänge bleibt so erhalten; ein älterer Stand kann keinen neueren überschreiben.
/// Bei jedem Schreiben werden außerdem Versionen je Ansatz und das tägliche Backup angelegt.
nonisolated final class JournalPersistence: @unchecked Sendable {
    enum LoadResult: Sendable {
        case empty
        case loaded([Project])
        case recoveredFromBackup([Project], preserved: URL)
        case failed(preserved: URL?)
    }

    let saveURL: URL
    let backupURL: URL
    /// Nur auf `queue` benutzen.
    let history: JournalHistory
    private let queue = DispatchQueue(label: "de.chemjournal.persistence", qos: .utility)
    /// Nur auf `queue` lesen/schreiben. `true`, wenn die Datei auf der Platte lesbar ist und als Backup taugt.
    private var mainFileIsValid = false
    /// Nur auf `queue`: Änderungsdatum der Datei nach unserem letzten Lesen/Schreiben.
    private var knownModificationDate: Date?

    convenience init(paths: AppPaths) {
        self.init(directory: paths.dataDirectory,
                  history: JournalHistory(versionsDirectory: paths.versionsDirectory, backupsDirectory: paths.backupsDirectory))
    }

    /// Journal in `directory`; Versionen und Backups in Unterordnern davon.
    convenience init(directory: URL) {
        self.init(directory: directory,
                  history: JournalHistory(versionsDirectory: directory.appendingPathComponent("Versionen", isDirectory: true),
                                          backupsDirectory: directory.appendingPathComponent("Backups", isDirectory: true)))
    }

    init(directory: URL, history: JournalHistory) {
        saveURL = directory.appendingPathComponent("ChemJournalData.json")
        backupURL = directory.appendingPathComponent("ChemJournalData.bak.json")
        self.history = history
    }

    func load() async -> LoadResult {
        await onQueue { self.loadSync() }
    }

    private func loadSync() -> LoadResult {
        let fm = FileManager.default
        ensureDownloaded()
        guard fm.fileExists(atPath: saveURL.path) else {
            if let p = decode(backupURL) { return .loaded(p) }
            return .empty
        }
        knownModificationDate = modificationDate()
        if let p = decode(saveURL) { mainFileIsValid = true; history.seed(p); return .loaded(p) }
        // Beschädigt: Original sichern, bevor irgendetwas überschrieben wird
        mainFileIsValid = false
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let preserved = saveURL.deletingLastPathComponent().appendingPathComponent("ChemJournalData.defekt-\(stamp).json")
        let didPreserve = (try? fm.copyItem(at: saveURL, to: preserved)) != nil
        if let p = decode(backupURL) { history.seed(p); return .recoveredFromBackup(p, preserved: preserved) }
        return .failed(preserved: didPreserve ? preserved : nil)
    }

    /// iCloud Drive lagert selten genutzte Dateien aus (Platzhalter „.…json.icloud“). Dann erst herunterladen lassen.
    private func ensureDownloaded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: saveURL.path) else { return }
        let placeholder = saveURL.deletingLastPathComponent().appendingPathComponent(".\(saveURL.lastPathComponent).icloud")
        guard fm.fileExists(atPath: placeholder.path) else { return }
        try? fm.startDownloadingUbiquitousItem(at: saveURL)
        for _ in 0..<120 where !fm.fileExists(atPath: saveURL.path) { Thread.sleep(forTimeInterval: 0.25) }
    }

    private func decode(_ url: URL) -> [Project]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Project].self, from: data)
    }

    private func modificationDate() -> Date? {
        (try? saveURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func save(_ projects: [Project]) {
        queue.async { self.write(projects, forceVersions: false) }
    }

    /// - Parameter forceVersions: Jede Änderung sofort als Version sichern (Beenden, Umzug), ohne Mindestabstand.
    func saveAndWait(_ projects: [Project], forceVersions: Bool = false) {
        queue.sync { self.write(projects, forceVersions: forceVersions) }
    }

    func waitForPendingWrites() {
        queue.sync { }
    }

    private func write(_ projects: [Project], forceVersions: Bool) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if mainFileIsValid, fm.fileExists(atPath: saveURL.path) {
            // Tägliches Backup = Stand vor der ersten Änderung des Tages
            history.dailyBackup(of: saveURL)
            // Nur eine lesbare Datei wird zum Backup – sonst würde ein defekter Stand das gute Backup ersetzen
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: saveURL, to: backupURL)
        }
        do {
            try data.write(to: saveURL, options: .atomic)
            mainFileIsValid = true
            knownModificationDate = modificationDate()
        } catch {
            print("ChemJournal: Speichern fehlgeschlagen: \(error)")
            return
        }
        history.recordChanges(projects, force: forceVersions)
    }

    /// Hat jemand anderes (iCloud) die Datei seit unserem letzten Lesen/Schreiben geändert? Dann neu laden; sonst `nil`.
    func reloadIfChangedExternally() async -> LoadResult? {
        await onQueue {
            guard let date = self.modificationDate(), date > (self.knownModificationDate ?? .distantPast) else { return nil }
            self.history.invalidateCaches()
            return self.loadSync()
        }
    }

    // MARK: Versionsverlauf (auf der Queue)

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in queue.async { continuation.resume(returning: work()) } }
    }

    func versions(for id: UUID) async -> [VersionInfo] { await onQueue { self.history.versions(for: id) } }
    func loadSnapshot(_ info: VersionInfo) async -> VersionSnapshot? { await onQueue { self.history.loadSnapshot(info) } }
    func deletedExperiments(existing: Set<UUID>) async -> [VersionInfo] { await onQueue { self.history.deletedExperiments(existing: existing) } }
    func removeHistory(for id: UUID) async { await onQueue { self.history.removeHistory(for: id) } }
    func backups() async -> [BackupInfo] { await onQueue { self.history.backups() } }
    func manualBackup() async -> URL? { await onQueue { self.history.manualBackup(of: self.saveURL) } }
    func safetyBackup() async -> URL? { await onQueue { self.history.safetyBackup(of: self.saveURL) } }
    func loadBackup(_ url: URL) async -> [Project]? { await onQueue { self.history.loadBackup(url) } }

    func snapshot(_ experiment: Experiment, project: Project?, reason: String, pinned: Bool) {
        queue.async { self.history.snapshot(experiment, project: project, reason: reason, pinned: pinned) }
    }
}
