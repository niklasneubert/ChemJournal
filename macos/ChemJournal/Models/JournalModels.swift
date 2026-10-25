import Foundation
import UniformTypeIdentifiers

// Die Modelle sind `nonisolated`, damit sie auch im Hintergrund (Smart Extract, Speichern) erzeugt
// und kodiert werden können. Das Projekt isoliert sonst standardmäßig alles auf den MainActor.

enum AppTheme: String, CaseIterable { case system = "System"; case light = "Hell"; case dark = "Dunkel" }

nonisolated struct ChemicalData: Identifiable, Hashable, Codable, Sendable {
    var id = UUID(); var name: String = ""; var equivalents: String = ""; var cas: String = ""; var molarMass: String = ""; var density: String = ""; var amount: String = ""; var volume: String = ""; var mass: String = ""
}

nonisolated struct YieldData: Identifiable, Hashable, Codable, Sendable {
    var id = UUID(); var name: String = ""; var cas: String = ""; var molarMass: String = ""; var density: String = ""; var amount: String = ""; var volume: String = ""; var mass: String = ""; var referenceChemicalID: UUID? = nil
}

nonisolated struct AnalysisFile: Identifiable, Hashable, Codable, Sendable { var id = UUID(); var filePath: String; var description: String = "" }

nonisolated struct Stage: Identifiable, Hashable, Codable, Sendable {
    var id = UUID(); var title: String; var sourceURL: String = ""; var summary: String = ""; var procedure: String = ""; var observation: String = ""; var chemicals: [ChemicalData] = []; var yieldProducts: [YieldData] = []; var reactionImageData: Data? = nil; var analysisFiles: [AnalysisFile] = []; var isExpanded: Bool = true; var createdAt: Date = Date()
}

nonisolated struct Experiment: Identifiable, Hashable, Codable, Sendable {
    var id = UUID(); var title: String; var summary: String; var stages: [Stage] = []; var createdAt: Date = Date(); var updatedAt: Date = Date()

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

enum SidebarItem: Hashable { case project(UUID); case experiment(UUID) }

extension UTType {
    static let chemjournal = UTType(exportedAs: "de.chemjournal.experiment")
}
