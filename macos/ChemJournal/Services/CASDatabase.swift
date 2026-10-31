import Foundation
import Observation

/// Ein gespeicherter CAS-Eintrag. Werte als Tabellen-Strings (M in g/mol, d in g/cm³).
nonisolated struct CASEntry: Codable, Equatable, Sendable, Identifiable {
    enum Source: String, Codable, Sendable {
        case user = "eigene Eingabe"
        case pubChem = "PubChem"

        /// Für die Anzeige (der Rohwert ist gespeichert und bleibt deutsch).
        var displayName: String { self == .user ? String(localized: "eigene Eingabe") : "PubChem" }
    }

    var cas: String
    var name: String
    var molarMass: String
    var density: String
    var source: Source
    var updatedAt: Date
    /// PubChem wurde zu dieser CAS bereits gefragt (z. B. ohne Dichte-Ergebnis) – nicht erneut fragen.
    var pubChemChecked: Bool

    var id: String { cas }
}

/// Lokale CAS-Datenbank: jede einmal eingegebene CAS-Nummer mit Molmasse und Dichte – egal ob die Werte
/// von dir stammen oder aus PubChem. Liegt als JSON-Datei neben dem Journal (lokal oder in iCloud Drive)
/// und funktioniert offline.
@Observable
final class CASDatabase {
    static let shared = CASDatabase(file: JournalStore.isRunningTests ? nil : AppPaths.current.casDatabaseFile,
                                    migrateLegacyDefaults: !JournalStore.isRunningTests)

    private(set) var entries: [String: CASEntry] = [:]
    @ObservationIgnored private var file: URL?
    @ObservationIgnored private let queue = DispatchQueue(label: "de.chemjournal.casdb", qos: .utility)

    /// - Parameter file: `nil` = nur im Speicher (Tests).
    init(file: URL?, migrateLegacyDefaults: Bool = false) {
        self.file = file
        if let file { entries = Self.read(file) }
        if migrateLegacyDefaults { migrateFromUserDefaults() }
    }

    var sortedEntries: [CASEntry] { entries.values.sorted { $0.updatedAt > $1.updatedAt } }

    func entry(for rawCAS: String) -> CASEntry? {
        guard let cas = CASNumber.normalized(rawCAS) else { return nil }
        return entries[cas]
    }

    /// Werte, die du selbst eingetippt hast. Leere Felder überschreiben keine vorhandenen Werte.
    func recordUserValues(cas rawCAS: String, name: String, molarMass: String, density: String) {
        guard let cas = CASNumber.normalized(rawCAS) else { return }
        var e = entries[cas] ?? CASEntry(cas: cas, name: "", molarMass: "", density: "", source: .user, updatedAt: Date(), pubChemChecked: false)
        let m = molarMass.trimmingCharacters(in: .whitespaces), d = density.trimmingCharacters(in: .whitespaces)
        guard !m.isEmpty || !d.isEmpty else { return }
        // Unverändert (z. B. nur durchs Feld geklickt) → Quelle und Datum nicht anfassen
        if let existing = entries[cas], (m.isEmpty || m == existing.molarMass), (d.isEmpty || d == existing.density) { return }
        if !m.isEmpty { e.molarMass = m }
        if !d.isEmpty { e.density = d }
        if e.name.isEmpty, !name.isEmpty { e.name = name }
        e.source = .user
        e.updatedAt = Date()
        store(e)
    }

    /// Ergebnis aus PubChem. Vorhandene eigene Werte bleiben; fehlende werden ergänzt.
    func recordPubChem(cas rawCAS: String, result: CASLookupService.Result) {
        guard let cas = CASNumber.normalized(rawCAS) else { return }
        let m = format3(result.molarMass), d = result.density.map(format4) ?? ""
        var e: CASEntry
        if var existing = entries[cas], existing.source == .user {
            if existing.molarMass.isEmpty { existing.molarMass = m }
            if existing.density.isEmpty { existing.density = d }
            if existing.name.isEmpty { existing.name = result.title }
            existing.pubChemChecked = true
            e = existing
        } else {
            e = CASEntry(cas: cas, name: result.title, molarMass: m, density: d, source: .pubChem, updatedAt: Date(), pubChemChecked: true)
        }
        e.updatedAt = Date()
        store(e)
    }

    /// PubChem war erreichbar, kannte den Stoff aber nicht – nicht bei jeder Eingabe erneut fragen.
    func markPubChemChecked(cas rawCAS: String) {
        guard let cas = CASNumber.normalized(rawCAS), var e = entries[cas] else { return }
        e.pubChemChecked = true
        store(e)
    }

    /// In den Einstellungen geänderte Werte: gelten als eigene Eingabe und haben damit Vorrang vor PubChem.
    /// Ein geleertes Feld löscht den Wert; Komma wird zum Dezimalpunkt wie in den Tabellen.
    func edit(cas: String, molarMass: String, density: String) {
        guard var e = entries[cas] else { return }
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".") }
        let m = clean(molarMass), d = clean(density)
        guard m != e.molarMass || d != e.density else { return }
        e.molarMass = m
        e.density = d
        e.source = .user
        e.updatedAt = Date()
        store(e)
    }

    func remove(cas: String) {
        entries[cas] = nil
        persist()
    }

    /// CAS-Nummern, deren gespeicherter Name zur Suche passt ("butyllithium" → 109-72-8).
    func casNumbers(matchingName normalizedTerm: String) -> Set<String> {
        guard normalizedTerm.count >= 3 else { return [] }
        return Set(entries.values.filter { SearchText.normalize($0.name).contains(normalizedTerm) }.map(\.cas))
    }

    // MARK: Speicherort

    /// Wechselt den Speicherort (z. B. nach iCloud Drive) und führt dabei die Einträge beider Dateien zusammen.
    func relocate(to newFile: URL) {
        let other = Self.read(newFile)
        for (cas, e) in other where (entries[cas]?.updatedAt ?? .distantPast) < e.updatedAt { entries[cas] = e }
        file = newFile
        persist()
    }

    /// Änderungen von einem anderen Mac (iCloud) übernehmen – neuerer Eintrag gewinnt.
    func reloadFromDisk() {
        guard let file else { return }
        var changed = false
        for (cas, e) in Self.read(file) where (entries[cas]?.updatedAt ?? .distantPast) < e.updatedAt {
            entries[cas] = e
            changed = true
        }
        if changed { persist() }
    }

    // MARK: intern

    private func store(_ e: CASEntry) {
        entries[e.cas] = e
        persist()
    }

    private func persist() {
        guard let file else { return }
        let snapshot = entries
        queue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot.values.sorted { $0.cas < $1.cas }) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { try data.write(to: file, options: .atomic) }
            catch { print("CAS-Datenbank: Speichern fehlgeschlagen: \(error)") }
        }
    }

    /// Wartet, bis alle Schreibvorgänge durch sind (Beenden, Tests).
    func waitForPendingWrites() { queue.sync { } }

    nonisolated static func read(_ file: URL) -> [String: CASEntry] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([CASEntry].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.cas, $0) }, uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b })
    }

    /// Übernimmt einmalig die alten Einträge aus den App-Einstellungen (nur gültige CAS-Nummern).
    private func migrateFromUserDefaults() {
        let flag = "casDatabaseMigrated"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flag) else { return }
        defer { defaults.set(true, forKey: flag) }
        struct Legacy: Decodable { var molarMass: String; var density: String }
        guard let data = defaults.data(forKey: "savedCASData"),
              let legacy = try? JSONDecoder().decode([String: Legacy].self, from: data) else { return }
        var imported = false
        for (rawCAS, values) in legacy {
            guard let cas = CASNumber.normalized(rawCAS), entries[cas] == nil,
                  !values.molarMass.isEmpty || !values.density.isEmpty else { continue }
            entries[cas] = CASEntry(cas: cas, name: "", molarMass: values.molarMass, density: values.density,
                                    source: .user, updatedAt: Date(), pubChemChecked: false)
            imported = true
        }
        if imported { persist() }
    }
}
