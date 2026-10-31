import Foundation
import Testing
@testable import ChemJournal

/// Die optimierte Suche muss genau dasselbe finden wie die bisherige. `ReferenceSearch` ist der Code der
/// Version 1.0.10 (unverändert übernommen).
@Suite("Suche: gleiche Ergebnisse wie vorher")
@MainActor
struct SearchEquivalenceTests {
    private struct ReferenceSearch {
        struct Term { let raw: String; let names: Set<String>; let cas: Set<String> }
        let terms: [Term]

        init(query: String, projects: [Project]) {
            let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
            let rows: [(name: String, cas: String)] = projects.flatMap(\.experiments).flatMap(\.stages).flatMap { stage in
                stage.chemicals.map { ($0.name, CASNumber.normalized($0.cas) ?? "") }
                    + stage.yieldProducts.map { ($0.name, CASNumber.normalized($0.cas) ?? "") }
            }
            terms = words.map { word in
                let norm = SearchText.normalize(word)
                var names: Set<String> = [norm]
                var cas: Set<String> = []
                if let c = CASNumber.normalized(word) { cas.insert(c) }
                if let group = ChemicalSynonyms.group(for: norm) {
                    cas.insert(group.cas)
                    names.formUnion(group.names.map(SearchText.normalize))
                }
                if norm.count >= 2 {
                    for row in rows where !row.cas.isEmpty && Self.nameMatches(row.name, names) { cas.insert(row.cas) }
                }
                return Term(raw: word.lowercased(), names: names, cas: cas)
            }
        }

        func hits(in experiment: Experiment) -> [SearchHit]? {
            guard !terms.isEmpty else { return [] }
            var hits: [SearchHit] = []
            for term in terms {
                var matched = textMatches(term, experiment)
                for stage in experiment.stages {
                    let rows = stage.chemicals.map { ($0.name, $0.cas, false) } + stage.yieldProducts.map { ($0.name, $0.cas, true) }
                    for (name, rawCAS, isProduct) in rows {
                        let c = CASNumber.normalized(rawCAS)
                        let byName = Self.nameMatches(name, term.names)
                        let byCAS = c.map { term.cas.contains($0) } ?? false
                        guard byName || byCAS else { continue }
                        matched = true
                        let display = name.isEmpty ? (c ?? rawCAS) : name
                        let casPart = (c != nil && !name.isEmpty) ? " (\(c!))" : ""
                        let hit = SearchHit(label: "\(display)\(casPart)\(isProduct ? String(localized: " – Produkt") : "") · \(stage.title)")
                        if !hits.contains(hit) { hits.append(hit) }
                    }
                }
                if !matched { return nil }
            }
            return hits
        }

        static func nameMatches(_ rowName: String, _ names: Set<String>) -> Bool {
            let whole = SearchText.normalize(rowName)
            guard !whole.isEmpty else { return false }
            lazy var words = Set(rowName.split(whereSeparator: { !$0.isLetter && !$0.isNumber && !"₀₁₂₃₄₅₆₇₈₉".contains($0) })
                .map { SearchText.normalize(String($0)) })
            for n in names where !n.isEmpty {
                if n.count > 3 { if whole.contains(n) { return true } }
                else if whole == n || words.contains(n) { return true }
            }
            return false
        }

        func textMatches(_ term: Term, _ e: Experiment) -> Bool {
            let q = term.raw
            if e.title.lowercased().contains(q) || e.summary.lowercased().contains(q) { return true }
            let tagQuery = q.hasPrefix("#") ? String(q.dropFirst()) : q
            if !tagQuery.isEmpty, e.tags.contains(where: { $0.lowercased().contains(tagQuery) }) { return true }
            return e.stages.contains { s in
                [s.title, s.summary, s.procedure, s.observation, s.sourceURL].contains { $0.lowercased().contains(q) }
                    || s.analyses.contains { $0.searchText.lowercased().contains(q) }
            }
        }
    }

    private func journal() -> [Project] {
        func chem(_ name: String, _ cas: String = "") -> ChemicalData { var c = ChemicalData(); c.name = name; c.cas = cas; return c }
        var exps: [Experiment] = []
        let names: [[ChemicalData]] = [
            [chem("n-BuLi", "109-72-8"), chem("THF (abs.)"), chem("CuBr2")],
            [chem("n-Butyllithium-Lösung"), chem("Br2"), chem("CH₂Cl₂", "75-09-2")],
            [chem("Carbazol (1)", "86-74-8"), chem("NaH (60 % in Mineralöl)", "7646-69-7"), chem("")],
            [chem("", "109-72-8"), chem("Ethylacetat"), chem("PE/EtOAc")],
            [chem("Pd(PPh3)4"), chem("K2CO3"), chem("Wasser")],
        ]
        for (i, rows) in names.enumerated() {
            var e = Experiment(title: ["Suzuki NK-12", "Heck", "SNAr 4CzBN", "Blindprobe", "ÄÖÜ ß Test"][i], summary: "Ansatz \(i)")
            e.tags = [["Scale-up"], [], ["Photokatalyse", "TADF"], ["#leer"], ["Überprüfen"]][i]
            var s = Stage(title: "Stufe \(i)")
            s.chemicals = rows
            var y = YieldData(); y.name = i % 2 == 0 ? "Produkt (3)" : "4CzBN"; y.cas = i == 1 ? "75-09-2" : ""
            s.yieldProducts = [y]
            s.procedure = ["Bei −78 °C in THF gerührt.", "Mit Kieselgel filtriert.", "NaH in DMF, dann (2a).", "", "Straße – Maßlösung"][i]
            s.analyses = i == 2 ? [AnalysisEntry(method: .nmr, values: ["solvent": "CDCl₃", "nucleus": "¹H"])] : []
            e.stages = [s, Stage(title: "Zweite \(i)")]
            exps.append(e)
        }
        return [Project(title: "P", experiments: exps)]
    }

    @Test("Viele Suchbegriffe: gleiche Treffer und gleiche Trefferzeilen")
    func equivalent() {
        let projects = journal()
        let queries = ["nbuli", "n-BuLi", "butyllithium", "109-72-8", "THF", "thf lösung", "br2", "CH2Cl2", "dcm", "dichlormethan",
                       "carbazol", "(1)", "nah", "mineralöl", "kieselgel", "#scale", "scale-up", "#", "photo tadf", "cdcl₃",
                       "nmr", "produkt", "4czbn", "ß", "STRASSE", "straße", "äöü", "überprüfen", "ethylacetat", "etoac",
                       "pd(pph3)4", "k2co3", "wasser", "stufe", "zweite", "−78", "x y", "Suzuki NK-12", "pe/etoac", "a"]
        for q in queries {
            let new = JournalSearch(query: q, projects: projects)
            let old = ReferenceSearch(query: q, projects: projects)
            for e in projects[0].experiments {
                #expect(new.hits(in: e) == old.hits(in: e), "Suche „\(q)“ in „\(e.title)“")
            }
        }
    }

    @Test("Zwischenspeicher der Seitenleiste: gleiche Eingaben → gleiches Ergebnis, Änderung → neu berechnen")
    func cache() {
        let cache = SearchResultCache()
        var projects = journal()
        cache.store((projects, [:]), query: "thf", projects: projects, casEntries: [:])
        #expect(cache.result(query: "thf", projects: projects, casEntries: [:]) != nil)
        #expect(cache.result(query: "thf ", projects: projects, casEntries: [:]) == nil)
        projects[0].experiments[0].title += "!"
        #expect(cache.result(query: "thf", projects: projects, casEntries: [:]) == nil)
    }
}
