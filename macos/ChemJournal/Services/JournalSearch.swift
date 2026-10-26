import Foundation

/// Suchtext vergleichbar machen: klein, ohne Leer-/Bindestriche/Punkte, Tief- und Fettziffern als normale Ziffern.
/// "n-BuLi" → "nbuli", "CH₂Cl₂" → "ch2cl2", "Verbindung 𝟏𝟐" → "verbindung12".
nonisolated enum SearchText {
    private static let digitFold: [Character: Character] = {
        var map: [Character: Character] = [:]
        let sub = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"], sup = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        for i in 0..<10 {
            let d = Character(String(i))
            map[Character(sub[i])] = d
            map[Character(sup[i])] = d
            map[Character(Unicode.Scalar(0x1D7CE + UInt32(i))!)] = d   // mathematische Fettziffern aus "(12)"
        }
        return map
    }()

    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "de_DE"))
        return String(folded.compactMap { c -> Character? in
            if let d = digitFold[c] { return d }
            if c.isWhitespace || "-–·.,()[]{}'’′/_".contains(c) { return nil }
            return c
        })
    }
}

/// Häufige Abkürzungen und Namen derselben Chemikalie (deutsch/englisch) mit CAS-Nummer.
/// Ergänzt die Suche: "n-BuLi" findet auch "n-Butyllithium" und Zeilen mit CAS 109-72-8.
nonisolated enum ChemicalSynonyms {
    struct Group { let cas: String; let names: [String] }

    static let groups: [Group] = [
        Group(cas: "109-72-8", names: ["n-BuLi", "BuLi", "n-Butyllithium", "Butyllithium", "n-butyllithium"]),
        Group(cas: "598-30-1", names: ["s-BuLi", "sec-BuLi", "sec-Butyllithium"]),
        Group(cas: "594-19-4", names: ["t-BuLi", "tert-BuLi", "tert-Butyllithium"]),
        Group(cas: "917-54-4", names: ["MeLi", "Methyllithium"]),
        Group(cas: "4111-54-0", names: ["LDA", "Lithiumdiisopropylamid", "lithium diisopropylamide"]),
        Group(cas: "4039-32-1", names: ["LiHMDS", "LHMDS", "Lithiumhexamethyldisilazid", "lithium bis(trimethylsilyl)amide"]),
        Group(cas: "1070-89-9", names: ["NaHMDS", "Natriumhexamethyldisilazid", "sodium bis(trimethylsilyl)amide"]),
        Group(cas: "40949-94-8", names: ["KHMDS", "Kaliumhexamethyldisilazid", "potassium bis(trimethylsilyl)amide"]),
        Group(cas: "75-16-1", names: ["MeMgBr", "Methylmagnesiumbromid", "methylmagnesium bromide"]),
        Group(cas: "109-99-9", names: ["THF", "Tetrahydrofuran"]),
        Group(cas: "75-09-2", names: ["DCM", "CH2Cl2", "Dichlormethan", "Methylenchlorid", "dichloromethane"]),
        Group(cas: "67-66-3", names: ["CHCl3", "Chloroform", "Trichlormethan"]),
        Group(cas: "68-12-2", names: ["DMF", "Dimethylformamid", "N,N-Dimethylformamid", "dimethylformamide"]),
        Group(cas: "67-68-5", names: ["DMSO", "Dimethylsulfoxid", "dimethyl sulfoxide"]),
        Group(cas: "75-05-8", names: ["MeCN", "CH3CN", "Acetonitril", "acetonitrile"]),
        Group(cas: "141-78-6", names: ["EtOAc", "AcOEt", "Ethylacetat", "Essigester", "Essigsäureethylester", "ethyl acetate"]),
        Group(cas: "60-29-7", names: ["Et2O", "Diethylether", "diethyl ether"]),
        Group(cas: "67-56-1", names: ["MeOH", "Methanol"]),
        Group(cas: "64-17-5", names: ["EtOH", "Ethanol"]),
        Group(cas: "67-63-0", names: ["iPrOH", "Isopropanol", "2-Propanol"]),
        Group(cas: "108-88-3", names: ["Toluol", "toluene", "PhMe"]),
        Group(cas: "110-54-3", names: ["Hexan", "n-Hexan", "hexane"]),
        Group(cas: "109-66-0", names: ["Pentan", "n-Pentan", "pentane"]),
        Group(cas: "67-64-1", names: ["Aceton", "acetone"]),
        Group(cas: "7732-18-5", names: ["H2O", "Wasser", "water"]),
        Group(cas: "121-44-8", names: ["Et3N", "NEt3", "TEA", "Triethylamin", "triethylamine"]),
        Group(cas: "7087-68-5", names: ["DIPEA", "DIEA", "Hünig-Base", "Diisopropylethylamin", "N,N-diisopropylethylamine"]),
        Group(cas: "108-18-9", names: ["Diisopropylamin", "iPr2NH", "DIPA", "diisopropylamine"]),
        Group(cas: "110-86-1", names: ["Pyridin", "pyridine"]),
        Group(cas: "1122-58-3", names: ["DMAP", "4-Dimethylaminopyridin"]),
        Group(cas: "6674-22-2", names: ["DBU"]),
        Group(cas: "584-08-7", names: ["K2CO3", "Kaliumcarbonat", "potassium carbonate"]),
        Group(cas: "534-17-8", names: ["Cs2CO3", "Cäsiumcarbonat", "cesium carbonate"]),
        Group(cas: "7646-69-7", names: ["NaH", "Natriumhydrid", "sodium hydride"]),
        Group(cas: "16940-66-2", names: ["NaBH4", "Natriumborhydrid", "sodium borohydride"]),
        Group(cas: "16853-85-3", names: ["LiAlH4", "LAH", "Lithiumaluminiumhydrid", "lithium aluminum hydride"]),
        Group(cas: "1191-15-7", names: ["DIBAL-H", "DIBAL", "DIBAH", "Diisobutylaluminiumhydrid"]),
        Group(cas: "76-05-1", names: ["TFA", "Trifluoressigsäure", "trifluoroacetic acid"]),
        Group(cas: "7647-01-0", names: ["HCl", "Salzsäure", "hydrochloric acid"]),
        Group(cas: "7664-93-9", names: ["H2SO4", "Schwefelsäure", "sulfuric acid"]),
        Group(cas: "64-19-7", names: ["AcOH", "Essigsäure", "acetic acid"]),
        Group(cas: "14221-01-3", names: ["Pd(PPh3)4", "Tetrakis(triphenylphosphin)palladium"]),
        Group(cas: "3375-31-3", names: ["Pd(OAc)2", "Palladium(II)-acetat", "palladium acetate"]),
        Group(cas: "603-35-0", names: ["PPh3", "Triphenylphosphin", "triphenylphosphine"]),
        Group(cas: "128-08-5", names: ["NBS", "N-Bromsuccinimid", "N-bromosuccinimide"]),
        Group(cas: "937-14-4", names: ["mCPBA", "m-CPBA", "meta-Chlorperbenzoesäure"]),
        Group(cas: "24424-99-5", names: ["Boc2O", "Di-tert-butyldicarbonat", "Boc-Anhydrid"]),
        Group(cas: "18162-48-6", names: ["TBSCl", "TBDMSCl", "tert-Butyldimethylsilylchlorid"]),
        Group(cas: "75-77-4", names: ["TMSCl", "Trimethylsilylchlorid", "chlorotrimethylsilane"]),
        Group(cas: "7226-23-5", names: ["DMPU"]),
        Group(cas: "680-31-9", names: ["HMPA", "Hexamethylphosphorsäuretriamid"]),
        Group(cas: "110-18-9", names: ["TMEDA", "Tetramethylethylendiamin"]),
        Group(cas: "7681-65-4", names: ["CuI", "Kupfer(I)-iodid", "copper(I) iodide"]),
        Group(cas: "7726-95-6", names: ["Br2", "Brom", "bromine"]),
        Group(cas: "7553-56-2", names: ["I2", "Iod", "Jod", "iodine"]),
        Group(cas: "1310-73-2", names: ["NaOH", "Natriumhydroxid", "Natronlauge", "sodium hydroxide"]),
        Group(cas: "1310-58-3", names: ["KOH", "Kaliumhydroxid", "Kalilauge", "potassium hydroxide"]),
        Group(cas: "865-47-4", names: ["KOtBu", "tBuOK", "Kalium-tert-butanolat", "potassium tert-butoxide"]),
        Group(cas: "10294-33-4", names: ["BBr3", "Bortribromid", "boron tribromide"]),
        Group(cas: "10025-87-3", names: ["POCl3", "Phosphorylchlorid", "phosphoryl chloride"]),
        Group(cas: "7719-09-7", names: ["SOCl2", "Thionylchlorid", "thionyl chloride"]),
        Group(cas: "79-37-8", names: ["(COCl)2", "Oxalylchlorid", "oxalyl chloride"]),
    ]

    /// normalisierter Name → Gruppe
    private static let index: [String: Group] = {
        var map: [String: Group] = [:]
        for g in groups { for n in g.names { map[SearchText.normalize(n)] = g } }
        return map
    }()

    /// Gruppe, deren Name genau dem Suchbegriff entspricht ("nbuli" → n-BuLi-Gruppe).
    static func group(for normalizedTerm: String) -> Group? { index[normalizedTerm] }
}

/// Ein Treffer in einer Tabellenzeile, für die Anzeige in der Seitenleiste.
nonisolated struct SearchHit: Hashable, Sendable {
    let label: String
}

/// Suche über das ganze Journal.
///
/// Jedes Wort der Suche muss im Ansatz vorkommen (UND). Ein Wort trifft:
/// - Titel, Beschreibung, Stufentitel, Zusammenfassung, Vorgehen, Beobachtung, Quelle (Text enthält das Wort),
/// - Chemikalien- und Produktnamen (auch "n-BuLi" ≈ "nBuLi", "CH₂Cl₂" ≈ "CH2Cl2"),
/// - Abkürzungen/Synonyme ("n-BuLi" findet "n-Butyllithium"),
/// - CAS-Nummern: direkt eingegeben, über die Synonymliste, über die lokale CAS-Datenbank ("Butyllithium" → 109-72-8)
///   und über das Journal selbst – heißt eine Zeile "n-BuLi" und hat CAS 109-72-8, findet "n-BuLi" auch alle
///   Zeilen mit dieser CAS-Nummer, egal wie sie benannt sind.
struct JournalSearch {
    private struct Term {
        let raw: String          // klein, für Volltext
        let normalized: String   // für Namen
        let names: Set<String>   // normalisierte Synonyme
        let cas: Set<String>
    }

    private let terms: [Term]

    var isEmpty: Bool { terms.isEmpty }

    init(query: String, projects: [Project], casDatabase: CASDatabase? = nil) {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        // Alle Zeilen des Journals einmal sammeln (Name normalisiert, CAS normalisiert)
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
            if let db = casDatabase { cas.formUnion(db.casNumbers(matchingName: norm)) }
            // Gleichwertigkeit über das Journal: Zeilen mit passendem Namen bringen ihre CAS mit
            if norm.count >= 2 {
                for row in rows where !row.cas.isEmpty && Self.nameMatches(row.name, names) {
                    cas.insert(row.cas)
                }
            }
            return Term(raw: word.lowercased(), normalized: norm, names: names, cas: cas)
        }
    }

    /// `nil`, wenn der Ansatz nicht passt; sonst die Treffer in Tabellenzeilen (kann leer sein, z. B. bei Titeltreffer).
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

    /// Lange Namen: enthalten ("butyllithium" in "n-Butyllithium-Lösung"). Kurze (≤ 3 Zeichen): als eigenes Wort
    /// ("THF" in "THF-Lösung", aber "Br2" nicht in "CuBr2").
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

    private func textMatches(_ term: Term, _ e: Experiment) -> Bool {
        let q = term.raw
        if e.title.lowercased().contains(q) || e.summary.lowercased().contains(q) { return true }
        return e.stages.contains { s in
            [s.title, s.summary, s.procedure, s.observation, s.sourceURL].contains { $0.lowercased().contains(q) }
        }
    }
}
