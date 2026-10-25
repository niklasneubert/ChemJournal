import Testing
@testable import ChemJournal

/// Muster aus echten Supporting Informations und Abschlussarbeiten (JACS, Chem. Eur. J., ChemSusChem, Molecules,
/// Vertiefungs-/Bachelorarbeiten). Die Sätze sind nachgebaut, nicht wörtlich übernommen.
@Suite("Smart Extract – Muster aus echten SIs")
struct RealWorldPatternTests {

    nonisolated private func rows(_ text: String) -> [[String]] {
        SmartExtractor(model: nil).extract(from: text).map { [$0.name, $0.equivalents, $0.amount, $0.volume, $0.mass] }
    }

    // MARK: Normalisierung

    @Test("PDF-Ersatzzeichen aus Symbol- und LaTeX-Schriften", arguments: [
        ("Aquivion\u{F0D2}PW98", "AquivionPW98"),
        ("25 \u{F0B0}C", "25 °C"),
        ("5 \u{F06D}L", "5 µL"),
        ("Celite®", "Celite"),
        ("bei 0¶C", "bei 0 °C"),
        ("2-Amino-↵, ↵,4-trimethylbenzol", "2-Amino-α,α,4-trimethylbenzol"),
    ])
    func pdfGlyphs(input: String, expected: String) {
        #expect(normalizeSynthesisText(input) == expected)
    }

    @Test("Einheiten und Funktionswörter, die an Namen kleben", arguments: [
        ("36.0mLBr2 (112 g)", "36.0 mL Br2 (112 g)"),
        ("mit 76.0mlCHCl3 vorgelegt", "mit 76.0 ml CHCl3 vorgelegt"),
        ("eq.) in1000 mL CH3CN", "eq.) in 1000 mL CH3CN"),
        ("in 60mLtrockenem DMF", "in 60 mL trockenem DMF"),
        ("bei0°Ctropfenweise addiert", "bei 0 °C tropfenweise addiert"),
    ])
    func gluedUnits(input: String, expected: String) {
        #expect(normalizeSynthesisText(input) == expected)
    }

    @Test("Flexionsendungen und Komposita bleiben ganz", arguments: [
        "frischumkristallisiertes", "Mineralöl", "Dreihalskolben", "Natriumsulfatlösung",
    ])
    func keepsWords(word: String) {
        #expect(normalizeSynthesisText(word) == word)
    }

    // MARK: Parser

    @Test("Satzende nach \"°C.\" – Aufarbeitung im Folgesatz löscht die Reagenzien nicht")
    func sentenceEndAfterDegree() {
        #expect(rows("Pyridine (1.2 mL, 15 mmol) was added at 0 °C. The mixture was washed with brine (20 mL).")
                == [["Pyridine", "", "0.015", "1.2", ""]])
    }

    @Test("Aufarbeitung wird nur im betroffenen Teilsatz verworfen")
    func clauseLevelWorkup() {
        #expect(rows("Benzoic acid (2.0 g, 16.4 mmol) was dissolved in SOCl2 (10 mL), which was heated to reflux for 2 h and then concentrated to afford the acid chloride.")
                == [["Benzoic acid", "", "0.0164", "", "2"], ["SOCl2", "", "", "10", ""]])
    }

    @Test("Quench, Gießen auf Wasser und Kieselgel sind Aufarbeitung")
    func workupSignals() {
        #expect(rows("The mixture was stirred for 2 h and poured into 100 mL water to quench the reaction.").isEmpty)
        #expect(rows("The reaction mixture was diluted with DCM (50 mL) followed by addition of silica gel (10 g).").isEmpty)
        #expect(rows("The mixture was stirred for 1 h prior to the addition of saturated aqueous NH4Cl (20 mL).").isEmpty)
    }

    @Test("\"a solution of X in S (V, n)\" – Mengen gehören zum gelösten Stoff")
    func solutionOfXInSolvent() {
        #expect(rows("A solution of n-BuLi in hexane (2.0 mL, 5.0 mmol) was added dropwise.") == [["n-BuLi", "", "0.005", "2", ""]])
        #expect(rows("Then a solution of oxalyl chloride in dry CH2Cl2 (2.0 M, 5.0 mL) was added.") == [["oxalyl chloride", "", "", "5", ""]])
        // Hat der gelöste Stoff schon Mengen, gehört die Klammer zum Lösemittel
        #expect(rows("A solution of 9 (0.27 g, 0.3 mmol) in THF (10 mL) was cooled.") == [["9", "", "0.0003", "", "0.27"], ["THF", "", "", "10", ""]])
    }

    @Test("Trägermedium in der Klammer: NaH als Suspension in Mineralöl")
    func carrierInParentheses() {
        #expect(rows("Es wurden 0.40 g NaH (60 wt-% Suspension in Mineralöl, 10 mmol, 2.0 eq.) zugegeben.") == [["NaH", "2", "0.01", "", "0.4"]])
    }

    @Test("Portionsgrößen und \"mol %\" mit Leerzeichen")
    func portionsAndMolPercent() {
        #expect(rows("Es wurden insgesamt 1.0 g NaBH4 (26 mmol, 2.0 eq.) in Portionen zu jeweils ca. 0.2 g zugegeben.") == [["NaBH4", "2", "0.026", "", "1"]])
        #expect(rows("Es wurden 10 mg ZnCl2 (0.5 mol %) in Toluol vorgelegt.").first == ["ZnCl2", "0.005", "", "", "0.01"])
    }

    @Test("Verweise auf Arbeitsvorschriften (AAV-2) sind keine Chemikalien")
    func procedureReferences() {
        let result = rows("Es wurden 1.00 eq. des nach AAV-2 hergestellten Amins 5 in Pyridin (2 ml) gelöst.")
        #expect(!result.contains { $0[0].hasPrefix("AAV") })
        #expect(result.contains(["Pyridin", "", "", "2", ""]))
    }

    @Test("Nomen vor Verbindungsnummer bleibt Teil des Namens, auch nach einem Komma")
    func labelNounAfterComma() {
        let result = rows("Aldehyde 1 (0.10 mmol) was added to dienyl alcohol 2 (0.10 mmol), catalyst 3b (0.005 mmol, 5 mol%) and toluene (1.0 mL).")
        #expect(result.contains(["catalyst 3b", "0.05", "0.000005", "", ""]))
    }

    @Test("\"crude (…) diol 7\" ist ein Edukt, kein Aufarbeitungssatz")
    func crudeAsReactant() {
        #expect(rows("Crude (2.0 g, 5.0 mmol, 80% purity) diol 7 was dissolved in MeOH (10 mL).")
                == [["diol 7", "", "0.005", "", "2"], ["MeOH", "", "", "10", ""]])
    }

    @Test("Verklebte Einheit, Mengen vor dem Namen")
    func gluedThesisStyle() {
        #expect(rows("Zu der Reaktionsmischung wurden 36.0mLBr2 (112 g, 702 mmol, 2.00 eq.)bei0°CtropfenweiseübereinenZeitraumvon1 h addiert.")
                == [["Br2", "2", "0.702", "36", "112"]])
    }
}
