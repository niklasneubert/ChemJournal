import Foundation
import UniformTypeIdentifiers

// Die Modelle sind `nonisolated`, damit sie auch im Hintergrund (Smart Extract, Speichern) erzeugt
// und kodiert werden können. Das Projekt isoliert sonst standardmäßig alles auf den MainActor.

enum AppTheme: String, CaseIterable { case system = "System"; case light = "Hell"; case dark = "Dunkel" }

nonisolated struct ChemicalData: Identifiable, Hashable, Codable, Sendable {
    var id = UUID(); var name: String = ""; var equivalents: String = ""; var cas: String = ""; var molarMass: String = ""; var density: String = ""; var amount: String = ""; var volume: String = ""; var mass: String = ""
    /// Reinheit in Prozent ("95"); leer = 100 %. `amount` ist die Stoffmenge des reinen Stoffes, `mass` und `volume`
    /// sind die abzumessende Menge des Reagenzes (m = n · M / Reinheit).
    var purity: String = ""

    /// Reinheit als Anteil (0 < p ≤ 1); leer oder ungültig = 1.
    var purityFraction: Double {
        let digits = purity.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let p = parseDecimal(digits), p > 0, p <= 100 else { return 1 }
        return p / 100
    }

    /// Abzuwiegende Masse (g) des Reagenzes für n mol reinen Stoff: m = n · M / Reinheit. `nil` ohne Molmasse.
    func massToWeigh(forAmount n: Double) -> Double? {
        guard let M = parseDecimal(molarMass), M > 0 else { return nil }
        return n * M / purityFraction
    }

    /// Stoffmenge (mol) reinen Stoffes in m g Reagenz: n = m · Reinheit / M. `nil` ohne Molmasse.
    func pureAmount(inMass m: Double) -> Double? {
        guard let M = parseDecimal(molarMass), M > 0 else { return nil }
        return m * purityFraction / M
    }

    private enum CodingKeys: String, CodingKey { case id, name, equivalents, cas, molarMass, density, amount, volume, mass, purity }
}

nonisolated extension ChemicalData {
    /// Liest auch Dateien älterer Versionen, in denen neuere Felder (z. B. `purity`) fehlen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: key) ?? "" }
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try text(.name); equivalents = try text(.equivalents); cas = try text(.cas); molarMass = try text(.molarMass)
        density = try text(.density); amount = try text(.amount); volume = try text(.volume); mass = try text(.mass)
        purity = try text(.purity)
    }
}

nonisolated struct YieldData: Identifiable, Hashable, Codable, Sendable {
    var id = UUID(); var name: String = ""; var cas: String = ""; var molarMass: String = ""; var density: String = ""; var amount: String = ""; var volume: String = ""; var mass: String = ""; var referenceChemicalID: UUID? = nil
}

nonisolated struct AnalysisFile: Identifiable, Hashable, Codable, Sendable { var id = UUID(); var filePath: String; var description: String = "" }

nonisolated struct Stage: Identifiable, Hashable, Codable, Sendable {
    var id = UUID(); var title: String; var sourceURL: String = ""; var summary: String = ""; var procedure: String = ""; var observation: String = ""; var chemicals: [ChemicalData] = []; var yieldProducts: [YieldData] = []; var reactionImageData: Data? = nil; var isExpanded: Bool = true; var createdAt: Date = Date()
    /// Aufreinigung & Analytik: Messungen (NMR, IR, MS …) und Aufreinigungsschritte (Säule, Umkristallisation …).
    var analyses: [AnalysisEntry] = []

    /// Alle verknüpften Dateien der Einträge.
    var analysisFiles: [AnalysisFile] { analyses.flatMap(\.files) }

    private enum CodingKeys: String, CodingKey {
        case id, title, sourceURL, summary, procedure, observation, chemicals, yieldProducts, reactionImageData, isExpanded, createdAt
        case analyses, analysisFiles
    }

    init(id: UUID = UUID(), title: String, sourceURL: String = "", summary: String = "", procedure: String = "", observation: String = "",
         chemicals: [ChemicalData] = [], yieldProducts: [YieldData] = [], reactionImageData: Data? = nil,
         isExpanded: Bool = true, createdAt: Date = Date(), analyses: [AnalysisEntry] = []) {
        self.id = id; self.title = title; self.sourceURL = sourceURL; self.summary = summary; self.procedure = procedure
        self.observation = observation; self.chemicals = chemicals; self.yieldProducts = yieldProducts
        self.reactionImageData = reactionImageData; self.isExpanded = isExpanded; self.createdAt = createdAt; self.analyses = analyses
    }

    /// Ältere Dateien haben nur `analysisFiles` (Dateiliste); daraus werden Einträge mit erratener Methode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceURL = try c.decode(String.self, forKey: .sourceURL)
        summary = try c.decode(String.self, forKey: .summary)
        procedure = try c.decode(String.self, forKey: .procedure)
        observation = try c.decode(String.self, forKey: .observation)
        chemicals = try c.decode([ChemicalData].self, forKey: .chemicals)
        yieldProducts = try c.decode([YieldData].self, forKey: .yieldProducts)
        reactionImageData = try c.decodeIfPresent(Data.self, forKey: .reactionImageData)
        isExpanded = try c.decode(Bool.self, forKey: .isExpanded)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if let entries = try c.decodeIfPresent([AnalysisEntry].self, forKey: .analyses) {
            analyses = entries
        } else {
            analyses = (try c.decodeIfPresent([AnalysisFile].self, forKey: .analysisFiles) ?? []).map(AnalysisEntry.migrated(from:))
        }
    }

    /// Schreibt zusätzlich die flache Dateiliste `analysisFiles`, damit ältere Versionen und die Linux-Version die
    /// verknüpften Dateien weiter sehen.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(sourceURL, forKey: .sourceURL)
        try c.encode(summary, forKey: .summary); try c.encode(procedure, forKey: .procedure); try c.encode(observation, forKey: .observation)
        try c.encode(chemicals, forKey: .chemicals); try c.encode(yieldProducts, forKey: .yieldProducts)
        try c.encodeIfPresent(reactionImageData, forKey: .reactionImageData)
        try c.encode(isExpanded, forKey: .isExpanded); try c.encode(createdAt, forKey: .createdAt)
        try c.encode(analyses, forKey: .analyses)
        try c.encode(analysisFiles, forKey: .analysisFiles)
    }
}

nonisolated struct Experiment: Identifiable, Hashable, Codable, Sendable {
    var id = UUID(); var title: String; var summary: String; var stages: [Stage] = []; var createdAt: Date = Date(); var updatedAt: Date = Date()
    /// Markiert (Stern), z. B. für wichtige oder offene Ansätze.
    var isMarked = false
    /// Eigene Tags zum Einordnen ("Photokatalyse", "Scale-up"). Ohne doppelte Einträge (Groß-/Kleinschreibung egal).
    var tags: [String] = []

    private enum CodingKeys: String, CodingKey { case id, title, summary, stages, createdAt, updatedAt, isMarked, tags }

    func hasTag(_ tag: String) -> Bool { tags.contains { JournalTag.same($0, tag) } }

    /// Fügt den Tag hinzu (bereinigt, ohne Dublette). `false`, wenn er leer ist oder schon da war.
    @discardableResult
    mutating func addTag(_ raw: String) -> Bool {
        guard let tag = JournalTag.clean(raw), !hasTag(tag) else { return false }
        tags.append(tag)
        return true
    }

    mutating func removeTag(_ tag: String) { tags.removeAll { JournalTag.same($0, tag) } }

    /// Volltextsuche über Titel, Beschreibung, Stufen und Chemikalien. `query` muss kleingeschrieben sein.
    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        if title.lowercased().contains(query) || summary.lowercased().contains(query) { return true }
        return stages.contains { s in
            s.title.lowercased().contains(query) || s.procedure.lowercased().contains(query) || s.observation.lowercased().contains(query)
                || s.chemicals.contains { $0.name.lowercased().contains(query) }
        }
    }
}

nonisolated struct Project: Identifiable, Hashable, Codable, Sendable { var id = UUID(); var title: String; var isExpanded: Bool = true; var experiments: [Experiment] = [] }

nonisolated extension Experiment {
    /// Liest auch Dateien älterer Versionen ohne Markierung und Tags. Die übrigen Felder bleiben Pflicht, damit eine
    /// fremde JSON-Datei beim Import weiter abgelehnt wird.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        stages = try c.decode([Stage].self, forKey: .stages)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isMarked = try c.decodeIfPresent(Bool.self, forKey: .isMarked) ?? false
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

/// Regeln für Tag-Namen.
nonisolated enum JournalTag {
    static let maxLength = 40

    /// Leerraum am Rand weg, innen zusammengefasst, ein führendes "#" entfernt; `nil`, wenn nichts übrig bleibt.
    static func clean(_ raw: String) -> String? {
        var t = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while t.hasPrefix("#") { t.removeFirst() }
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return String(t.prefix(maxLength))
    }

    static func same(_ a: String, _ b: String) -> Bool { a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }

    /// Alle Tags im Journal, alphabetisch, jeder nur einmal (in der Schreibweise des ersten Vorkommens).
    static func all(in projects: [Project]) -> [String] {
        var seen: [String] = []
        for tag in projects.flatMap(\.experiments).flatMap(\.tags) where !seen.contains(where: { same($0, tag) }) {
            seen.append(tag)
        }
        return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Benennt einen Tag in allen Ansätzen um. Gibt es den neuen Namen in einem Ansatz schon, werden beide zusammengelegt.
    static func rename(_ old: String, to raw: String, in projects: inout [Project]) {
        guard let new = clean(raw) else { return }
        for p in projects.indices {
            for e in projects[p].experiments.indices where projects[p].experiments[e].hasTag(old) {
                var exp = projects[p].experiments[e]
                let position = exp.tags.firstIndex { same($0, old) } ?? exp.tags.count
                exp.removeTag(old)
                if exp.hasTag(new) {
                    exp.tags = exp.tags.map { same($0, new) ? new : $0 }
                } else {
                    exp.tags.insert(new, at: min(position, exp.tags.count))
                }
                projects[p].experiments[e] = exp
            }
        }
    }

    /// Entfernt einen Tag aus allen Ansätzen.
    static func delete(_ tag: String, in projects: inout [Project]) {
        for p in projects.indices {
            for e in projects[p].experiments.indices where projects[p].experiments[e].hasTag(tag) {
                projects[p].experiments[e].removeTag(tag)
            }
        }
    }
}

enum SidebarItem: Hashable { case project(UUID); case experiment(UUID) }

extension UTType {
    static let chemjournal = UTType(exportedAs: "de.chemjournal.experiment")
}
