import Testing
@testable import ChemJournal

/// Erwartete Tabellenzeile (Werte so, wie sie in der Tabelle stehen).
nonisolated private struct Row: Equatable, CustomStringConvertible {
    var name: String, eq = "", n = "", V = "", m = ""
    init(_ name: String, eq: String = "", n: String = "", V: String = "", m: String = "") {
        self.name = name; self.eq = eq; self.n = n; self.V = V; self.m = m
    }
    init(_ c: ChemicalData) { self.init(c.name, eq: c.equivalents, n: c.amount, V: c.volume, m: c.mass) }
    var description: String { "\(name) | eq \(eq) | n \(n) | V \(V) | m \(m)" }
}

nonisolated private func extractRows(_ text: String) -> [Row] {
    SmartExtractor(model: nil).extract(from: text).map(Row.init)
}

@Suite("Smart Extract – Parser")
struct SmartExtractorTests {

    /// Das Ergebnis, das die Case Study liefern muss (vorher: 8 Zeilen, davon 5 falsch).
    fileprivate static let caseStudyRows = [
        Row("Diisopropylamin", eq: "0.95", n: "0.0465", V: "6.55"),
        Row("THF", V: "40"),
        Row("n-Butyllithium", eq: "0.95", n: "0.0465", V: "18.6"),
        Row("DMPU", V: "45"),
        Row("7", eq: "1", n: "0.048", V: "5"),
        Row("4", eq: "1.1", n: "0.0538", V: "6.8"),
    ]

    @Test("Case Study: alle sechs Zeilen korrekt (regelbasiert)")
    func caseStudyRuleBased() {
        #expect(extractRows(SynthesisTextNormalizerTests.caseStudyInput) == Self.caseStudyRows)
    }

    @Test("Case Study: alle sechs Zeilen korrekt (mit eingebettetem Modell)")
    func caseStudyWithModel() async {
        let rows = await SmartExtractService.shared.extract(from: SynthesisTextNormalizerTests.caseStudyInput).map(Row.init)
        #expect(await SmartExtractService.shared.loadedModelName == "Smart Extract for ChemJournal 15", "Modell 15 wurde nicht geladen")
        #expect(rows == Self.caseStudyRows)
    }

    @Test("Molarität mit Trägerlösemittel: 2.5 M in hexanes")
    func molarityCarrier() {
        let rows = extractRows("To a solution of benzaldehyde (1.06 g, 10.0 mmol, 1.0 equiv.) in THF (20 mL) was added n-BuLi (2.5 M in hexanes, 4.4 mL, 11 mmol) at -78 °C.")
        #expect(rows == [
            Row("benzaldehyde", eq: "1", n: "0.01", m: "1.06"),
            Row("THF", V: "20"),
            Row("n-BuLi", n: "0.011", V: "4.4"),
        ])
    }

    @Test("Katalysatorbeladung in mol% und Pd/C mit Prozentangabe")
    func catalystLoading() {
        let rows = extractRows("4-Nitrostyrene (746 mg, 5.00 mmol, 1.0 equiv) was dissolved in 25 mL ethanol and treated with 10% Pd/C (26.6 mg, 5 mol%) under 1 atm H2 for 4 h.")
        #expect(rows.contains(Row("4-Nitrostyrene", eq: "1", n: "0.005", m: "0.746")))
        #expect(rows.contains(Row("ethanol", V: "25")))
        #expect(rows.contains(Row("10% Pd/C", eq: "0.05", m: "0.0266")))
    }

    @Test("Hydrat und Salz ohne Formel-Schreibweise")
    func hydrateAndSalt() {
        let rows = extractRows("CuSO4 · 5 H2O (12.5 mg, 0.05 mmol, 5 mol%) und Natriumascorbat (19.8 mg, 0.10 mmol) wurden in 2 mL Wasser gelöst.")
        #expect(rows == [
            Row("CuSO4·5H2O", eq: "0.05", n: "0.00005", m: "0.0125"),
            Row("Natriumascorbat", n: "0.0001", m: "0.0198"),
            Row("Wasser", V: "2"),
        ])
    }

    @Test("Kolbenvolumen ist keine Ansatzgröße")
    func apparatusVolume() {
        let rows = extractRows("In einem 2L Rundkolben wurden 130.0 g 70 (349.3 mmol, 1.000 eq.) in 1000 mL CH3CN vorgelegt.")
        #expect(rows == [Row("70", eq: "1", n: "0.3493", m: "130"), Row("CH3CN", V: "1000")])
    }

    @Test("Aufarbeitungssätze werden ignoriert")
    func workupIgnored() {
        let rows = extractRows("Die organische Phase wurde mit 20 mL Brine gewaschen und über MgSO4 getrocknet. The mixture was extracted with EtOAc (3 × 20 mL).")
        #expect(rows.isEmpty)
    }

    @Test("Klammern im Namen bleiben erhalten")
    func bracketsInNames() {
        let rows = extractRows("(S)-BINOL (286 mg, 1.00 mmol) und Pd(PPh3)4 (57.8 mg, 0.05 mmol) wurden in einem 25 ml Schlenkkolben vorgelegt.")
        #expect(rows == [Row("(S)-BINOL", n: "0.001", m: "0.286"), Row("Pd(PPh3)4", n: "0.00005", m: "0.0578")])
    }

    @Test("Kurzname in Klammern wird nicht zur eigenen Zeile")
    func aliasInParentheses() {
        let rows = extractRows("Ethyl acetate (EtOAc, 2.0 mL) was added.")
        #expect(rows == [Row("Ethyl acetate", V: "2")])
    }

    @Test("Mengen ohne Leerzeichen und deutsches Dezimalkomma")
    func gluedAndCommaDecimals() {
        let rows = extractRows("Es wurden 298.0mg (2,98 mmol, 1,5 Äq.) Benzaldehyd vorgelegt.")
        #expect(rows == [Row("Benzaldehyd", eq: "1.5", n: "0.00298", m: "0.298")])
    }

    @Test("Temperaturen und Zeiten werden nie zu Chemikalien")
    func temperaturesAndTimes() {
        let rows = extractRows("Die Lösung wurde auf -78 °C gekühlt und nach 30 min bei 0 °C für 2 h gerührt.")
        #expect(rows.isEmpty)
    }
}
