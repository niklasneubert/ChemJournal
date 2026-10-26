import Foundation
import Testing
@testable import ChemJournal

private func tempDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ChemJournalTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func experiment(_ title: String, chemicals: [(String, String)] = [], procedure: String = "") -> Experiment {
    var stage = Stage(title: "Stufe 1")
    stage.chemicals = chemicals.map { ChemicalData(name: $0.0, cas: $0.1) }
    stage.procedure = procedure
    return Experiment(title: title, summary: "", stages: [stage])
}

// MARK: - CAS-Datenbank

@Suite("Lokale CAS-Datenbank")
@MainActor
struct CASDatabaseTests {

    @Test("Eigene Werte werden gespeichert und nach Neustart offline gefunden")
    func userValuesPersist() throws {
        let file = try tempDirectory().appendingPathComponent("CAS-Datenbank.json")
        let db = CASDatabase(file: file)
        db.recordUserValues(cas: "109-72-8", name: "n-BuLi", molarMass: "64.06", density: "0.68")
        db.waitForPendingWrites()

        let reopened = CASDatabase(file: file)
        let e = try #require(reopened.entry(for: "109‑72‑8"))   // auch mit Unicode-Bindestrich
        #expect(e.molarMass == "64.06")
        #expect(e.density == "0.68")
        #expect(e.source == .user)
    }

    @Test("Ungültige CAS-Nummern werden nicht gespeichert")
    func invalidCASIgnored() {
        let db = CASDatabase(file: nil)
        db.recordUserValues(cas: "109-72-9", name: "x", molarMass: "1", density: "1")   // falsche Prüfziffer
        #expect(db.entries.isEmpty)
    }

    @Test("PubChem ergänzt nur fehlende Werte – eigene bleiben")
    func pubChemKeepsUserValues() throws {
        let db = CASDatabase(file: nil)
        db.recordUserValues(cas: "109-99-9", name: "THF", molarMass: "", density: "0.889")
        db.recordPubChem(cas: "109-99-9", result: .init(title: "Tetrahydrofuran", molarMass: 72.11, density: 0.8833))
        let e = try #require(db.entry(for: "109-99-9"))
        #expect(e.density == "0.889")
        #expect(e.molarMass == "72.11")
        #expect(e.source == .user)
        #expect(e.pubChemChecked)
    }

    @Test("Unveränderte Werte ändern Quelle und Datum nicht")
    func unchangedValuesNoop() throws {
        let db = CASDatabase(file: nil)
        db.recordPubChem(cas: "75-09-2", result: .init(title: "Dichloromethane", molarMass: 84.93, density: 1.3255))
        let before = try #require(db.entry(for: "75-09-2"))
        db.recordUserValues(cas: "75-09-2", name: "DCM", molarMass: before.molarMass, density: before.density)
        #expect(db.entry(for: "75-09-2") == before)
    }

    @Test("Umzug führt beide Dateien zusammen, neuerer Eintrag gewinnt")
    func relocateMerges() throws {
        let dir = try tempDirectory()
        let a = dir.appendingPathComponent("a.json"), b = dir.appendingPathComponent("b.json")
        let other = CASDatabase(file: b)
        other.recordUserValues(cas: "7681-65-4", name: "CuI", molarMass: "190.45", density: "5.67")
        other.waitForPendingWrites()

        let db = CASDatabase(file: a)
        db.recordUserValues(cas: "109-72-8", name: "n-BuLi", molarMass: "64.06", density: "0.68")
        db.relocate(to: b)
        db.waitForPendingWrites()
        #expect(Set(CASDatabase.read(b).keys) == ["7681-65-4", "109-72-8"])
    }
}

// MARK: - Suche

@Suite("Journal-Suche")
@MainActor
struct JournalSearchTests {

    private func project(_ experiments: [Experiment]) -> [Project] { [Project(title: "P", experiments: experiments)] }

    @Test("„n-BuLi“ findet Ansätze mit n-Butyllithium, BuLi oder nur der CAS-Nummer")
    func buLiSynonyms() {
        let a = experiment("A", chemicals: [("n-Butyllithium (2.5 M in Hexan)", "")])
        let b = experiment("B", chemicals: [("BuLi", "")])
        let c = experiment("C", chemicals: [("", "109-72-8")])
        let d = experiment("D", chemicals: [("LDA", "4111-54-0")])
        let projects = project([a, b, c, d])
        let search = JournalSearch(query: "n-BuLi", projects: projects)
        #expect(search.hits(in: a) != nil)
        #expect(search.hits(in: b) != nil)
        #expect(search.hits(in: c) != nil)
        #expect(search.hits(in: d) == nil)
    }

    @Test("Eigene Bezeichnung + CAS: Suche nach dem Namen findet auch Zeilen, die nur die CAS haben")
    func casEquivalenceThroughJournal() {
        let a = experiment("A", chemicals: [("Ligand L1", "2622-14-2")])
        let b = experiment("B", chemicals: [("PCy3", "2622-14-2")])
        let projects = project([a, b])
        #expect(JournalSearch(query: "Ligand L1", projects: projects).hits(in: b) != nil)
    }

    @Test("Kurze Namen nur als ganzes Wort („Br2“ nicht in „CuBr2“)")
    func shortNamesWordLevel() {
        #expect(JournalSearch.nameMatches("Br2", ["br2"]))
        #expect(!JournalSearch.nameMatches("CuBr2", ["br2"]))
        #expect(JournalSearch.nameMatches("THF (abs.)", ["thf"]))
    }

    @Test("Mehrere Wörter: alle müssen vorkommen (UND); Treffer zeigen Zeile und Stufe")
    func andSearchWithHits() throws {
        let a = experiment("Suzuki", chemicals: [("Pd(PPh3)4", "14221-01-3"), ("THF", "109-99-9")])
        let b = experiment("Grignard", chemicals: [("THF", "109-99-9")])
        let projects = project([a, b])
        let search = JournalSearch(query: "THF Pd(PPh3)4", projects: projects)
        let hits = try #require(search.hits(in: a))
        #expect(search.hits(in: b) == nil)
        #expect(hits.contains { $0.label == "THF (109-99-9) · Stufe 1" })
    }

    @Test("Volltext in Vorgehen und CAS-Eingabe direkt")
    func fullTextAndDirectCAS() {
        let a = experiment("A", chemicals: [("Toluol", "108-88-3")], procedure: "Unter Argon bei −78 °C gerührt")
        let projects = project([a])
        #expect(JournalSearch(query: "argon", projects: projects).hits(in: a) != nil)
        #expect(JournalSearch(query: "108-88-3", projects: projects).hits(in: a) != nil)
    }

    @Test("Name aus der lokalen CAS-Datenbank führt zur CAS-Nummer")
    func casDatabaseNames() {
        let db = CASDatabase(file: nil)
        db.recordPubChem(cas: "7681-65-4", result: .init(title: "Copper(I) iodide", molarMass: 190.45, density: 5.67))
        let a = experiment("A", chemicals: [("CuI", "7681-65-4")])
        #expect(JournalSearch(query: "copperiiodide", projects: project([a]), casDatabase: db).hits(in: a) != nil)
    }

    @Test("Alle CAS-Nummern der Synonymliste haben eine gültige Prüfziffer")
    func synonymChecksums() {
        for g in ChemicalSynonyms.groups { #expect(CASNumber.isValid(g.cas), "\(g.cas) \(g.names)") }
    }
}

// MARK: - Versionsverlauf & Backups

@Suite("Versionsverlauf und Backups")
struct JournalHistoryTests {

    private func makeHistory(_ dir: URL) -> JournalHistory {
        JournalHistory(versionsDirectory: dir.appendingPathComponent("Versionen"),
                       backupsDirectory: dir.appendingPathComponent("Backups"), minimumInterval: 600)
    }

    @Test("Erste Sicherung, dann Mindestabstand; nach der Pause wird der Stand davor gesichert")
    func automaticVersions() throws {
        let history = makeHistory(try tempDirectory())
        var e = experiment("Ansatz")
        var project = Project(title: "P", experiments: [e])
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        history.recordChanges([project], now: t0)
        #expect(history.versions(for: e.id).map(\.reason) == ["Erste Sicherung"])

        // Änderung nach 1 Minute: noch keine neue Version
        e.title = "Ansatz B"; project.experiments = [e]
        history.recordChanges([project], now: t0 + 60)
        #expect(history.versions(for: e.id).count == 1)

        // Lange Pause, dann weitere Änderung: Zwischenstand „Ansatz B“ wird gesichert
        e.title = "Ansatz C"; project.experiments = [e]
        history.recordChanges([project], now: t0 + 3600)
        let versions = history.versions(for: e.id)
        #expect(versions.count == 2)
        #expect(versions.first?.title == "Ansatz B")

        // Beim Beenden: aktueller Stand sofort
        history.recordChanges([project], now: t0 + 3660, force: true)
        #expect(history.versions(for: e.id).first?.title == "Ansatz C")
        #expect(history.versions(for: e.id).count == 3)

        // Erneut beenden ohne Änderung: keine doppelte Version
        history.recordChanges([project], now: t0 + 3700, force: true)
        #expect(history.versions(for: e.id).count == 3)
    }

    @Test("Version lässt sich vollständig laden")
    func loadSnapshot() throws {
        let history = makeHistory(try tempDirectory())
        let e = experiment("Grignard", chemicals: [("Mg", "7439-95-4")])
        let project = Project(title: "Projekt X", experiments: [e])
        history.recordChanges([project])
        let info = try #require(history.versions(for: e.id).first)
        let snap = try #require(history.loadSnapshot(info))
        // Datumswerte werden sekundengenau gespeichert – Inhalt vergleichen
        #expect(snap.experiment.id == e.id)
        #expect(snap.experiment.title == e.title)
        #expect(snap.experiment.stages.map(\.id) == e.stages.map(\.id))
        #expect(snap.experiment.stages.first?.chemicals == e.stages.first?.chemicals)
        #expect(abs(snap.experiment.createdAt.timeIntervalSince(e.createdAt)) < 1)
        #expect(snap.projectTitle == "Projekt X")
        #expect(info.chemicalCount == 1)
    }

    @Test("Gelöschte Ansätze bleiben auffindbar, bis der Verlauf entfernt wird")
    func deletedExperiments() throws {
        let history = makeHistory(try tempDirectory())
        let keep = experiment("Bleibt"), gone = experiment("Gelöscht")
        let project = Project(title: "P", experiments: [keep, gone])
        history.recordChanges([project])
        history.snapshot(gone, project: project, reason: "Vor dem Löschen", pinned: true)

        let deleted = history.deletedExperiments(existing: [keep.id])
        #expect(deleted.map(\.experimentID) == [gone.id])
        #expect(deleted.first?.pinned == true)

        history.removeHistory(for: gone.id)
        #expect(history.deletedExperiments(existing: [keep.id]).isEmpty)
    }

    @Test("Ausdünnen: ältere Versionen eine pro Tag, angeheftete bleiben")
    func pruning() throws {
        let history = makeHistory(try tempDirectory())
        var e = experiment("Ansatz")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // 3 Tage lang alle 2 Stunden eine Version
        for i in 0..<36 {
            e.summary = "Stand \(i)"
            history.snapshot(e, project: nil, reason: "Test", pinned: i == 1, now: start + Double(i) * 7200)
        }
        let now = start + 35 * 7200
        let versions = history.versions(for: e.id)
        let recent = versions.filter { now.timeIntervalSince($0.date) < 86_400 }
        #expect(recent.count == 12)                          // letzte 24 h vollständig
        #expect(versions.contains { $0.pinned })             // angeheftete bleibt
        #expect(versions.count < 36)
    }

    @Test("Tägliches Backup nur einmal pro Tag, manuelles immer")
    func dailyBackup() throws {
        let dir = try tempDirectory()
        let history = makeHistory(dir)
        let journal = dir.appendingPathComponent("ChemJournalData.json")
        try Data("[]".utf8).write(to: journal)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(history.dailyBackup(of: journal, now: day) != nil)
        #expect(history.dailyBackup(of: journal, now: day + 60) == nil)
        #expect(history.manualBackup(of: journal, now: day + 120) != nil)
        #expect(history.backups().count == 2)
    }

    @Test("Speichern legt Versionen und das tägliche Backup automatisch an")
    func persistenceCreatesHistory() async throws {
        let dir = try tempDirectory()
        let persistence = JournalPersistence(directory: dir)
        let e = experiment("Ansatz")
        persistence.saveAndWait([Project(title: "P", experiments: [e])])
        #expect(await persistence.versions(for: e.id).count == 1)

        var changed = e; changed.title = "Neu"
        persistence.saveAndWait([Project(title: "P", experiments: [changed])])   // Datei existiert jetzt → Backup
        #expect(await persistence.backups().count == 1)
    }
}

// MARK: - Speicherort-Wechsel

@Suite("Speicherort wechseln")
@MainActor
struct StorageSwitchTests {

    private func paths(_ dir: URL) -> AppPaths {
        AppPaths(dataDirectory: dir, supportDirectory: dir.appendingPathComponent("Support"))
    }

    @Test("Umzug in einen leeren Ordner nimmt Journal und Versionen mit; alter Ort bleibt unverändert")
    func moveToEmptyTarget() async throws {
        let source = paths(try tempDirectory()), target = paths(try tempDirectory())
        let store = JournalStore(paths: source)
        await store.loadIfNeeded()
        let e = experiment("Ansatz")
        store.projects = [Project(title: "P", experiments: [e])]
        store.waitForPendingWrites()

        #expect(await store.checkSwitch(to: target) == .ready)
        await store.switchStorage(to: target, mode: .local, useExistingJournal: false, casDatabase: nil)

        #expect(store.paths == target)
        #expect(FileManager.default.fileExists(atPath: target.journalFile.path))
        #expect(FileManager.default.fileExists(atPath: source.journalFile.path))
        #expect(await store.versions(for: e.id).isEmpty == false)
    }

    @Test("Backup zurückspielen: aktueller Stand wird vorher gesichert und lässt sich widerrufen")
    func restoreBackup() async throws {
        let p = paths(try tempDirectory())
        let store = JournalStore(paths: p)
        await store.loadIfNeeded()
        store.projects = [Project(title: "Alt", experiments: [experiment("Alt")])]
        store.waitForPendingWrites()
        guard let backup = await store.backupNow() else { Issue.record("kein Backup"); return }
        store.projects = [Project(title: "Neu", experiments: [experiment("Neu")])]
        store.waitForPendingWrites()

        let info = BackupInfo(url: backup, date: Date(), size: 0)
        guard case .restored(let safety) = await store.restoreBackup(info) else { Issue.record("nicht wiederhergestellt"); return }
        #expect(store.projects.map(\.title) == ["Alt"])
        let safetyURL = try #require(safety)
        #expect(safetyURL.lastPathComponent.hasPrefix("ChemJournal-vor-Wiederherstellen-"))
        let saved = try JSONDecoder().decode([Project].self, from: Data(contentsOf: safetyURL))
        #expect(saved.map(\.title) == ["Neu"])
        store.waitForPendingWrites()
        let onDisk = try JSONDecoder().decode([Project].self, from: Data(contentsOf: p.journalFile))
        #expect(onDisk.map(\.title) == ["Alt"])
        #expect(store.undo())
        #expect(store.projects.map(\.title) == ["Neu"])

        let broken = p.backupsDirectory.appendingPathComponent("kaputt.json")
        try Data("kein json".utf8).write(to: broken)
        #expect(await store.restoreBackup(BackupInfo(url: broken, date: Date(), size: 0)) == .unreadable)
    }

    @Test("Liegt am Ziel schon ein Journal, kann es übernommen werden – das bisherige wird als Backup aufbewahrt")
    func useExistingTarget() async throws {
        let source = paths(try tempDirectory()), target = paths(try tempDirectory())
        let remote = experiment("Vom anderen Mac")
        JournalPersistence(paths: target).saveAndWait([Project(title: "Remote", experiments: [remote])])

        let store = JournalStore(paths: source)
        await store.loadIfNeeded()
        store.projects = [Project(title: "Lokal", experiments: [experiment("Lokal")])]
        store.waitForPendingWrites()

        guard case .targetHasJournal(let n, _) = await store.checkSwitch(to: target) else {
            Issue.record("Konflikt nicht erkannt"); return
        }
        #expect(n == 1)
        await store.switchStorage(to: target, mode: .local, useExistingJournal: true, casDatabase: nil)
        #expect(store.projects.map(\.title) == ["Remote"])
        let backups = try FileManager.default.contentsOfDirectory(atPath: target.backupsDirectory.path)
        #expect(backups.contains { $0.hasPrefix("ChemJournal-vor-Umzug-") })
    }
}
