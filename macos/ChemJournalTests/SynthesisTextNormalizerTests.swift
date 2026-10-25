import Testing
@testable import ChemJournal

/// Regressionstests für die PDF-Bereinigung vor Smart Extract.
@Suite("Text-Normalisierung")
struct SynthesisTextNormalizerTests {

    static let caseStudyInput = "Zunächst wurden 6.55 ml (46.5 mmol, 0.95 eq) Diisopropylamin in 40 ml THF vorgelegt. Die Lösungwurdeauf0 •C abgekühltund18.6 ml (46.5 mmol,0.95 eq)einer2.5M n-Butyllithium-Lösung zugegeben. Die Lösung wurde auf–78•C abgekühlt und anschließend 45 ml DMPU addiert. Nach 5 Minuten wurden 5.00 ml (48.0 mmol, 1.00 eq) von 7 als THF-Lösung zuge-tropft.Nachweiteren15Minutenwurde6.80 ml (53.8 mmol,1.10 eq)4 addiertunddieLösung für 45 Minuten gerührt."

    static let caseStudyExpected = "Zunächst wurden 6.55 ml (46.5 mmol, 0.95 eq) Diisopropylamin in 40 ml THF vorgelegt. Die Lösung wurde auf 0 °C abgekühlt und 18.6 ml (46.5 mmol, 0.95 eq) einer 2.5 M n-Butyllithium-Lösung zugegeben. Die Lösung wurde auf -78 °C abgekühlt und anschließend 45 ml DMPU addiert. Nach 5 Minuten wurden 5.00 ml (48.0 mmol, 1.00 eq) von 7 als THF-Lösung zugetropft. Nach weiteren 15 Minuten wurde 6.80 ml (53.8 mmol, 1.10 eq) 4 addiert und die Lösung für 45 Minuten gerührt."

    @Test("Case Study aus der Dissertation wird vollständig repariert")
    func caseStudy() {
        #expect(normalizeSynthesisText(Self.caseStudyInput) == Self.caseStudyExpected)
    }

    @Test("Einzelne Reparaturen", arguments: [
        // 1. Verklebte Wörter und Zahlen
        ("abgekühltund18.6 ml", "abgekühlt und 18.6 ml"),
        ("wurde6.80 ml", "wurde 6.80 ml"),
        ("Nachweiteren15Minutenwurde6.80 ml", "Nach weiteren 15 Minuten wurde 6.80 ml"),
        ("Lösungwurdeauf0 °C", "Lösung wurde auf 0 °C"),
        ("einer2.5M Lösung", "einer 2.5 M Lösung"),
        ("298.0mg", "298.0 mg"),
        ("313µL", "313 µL"),
        ("1.9eq", "1.9 eq"),
        ("10mol%", "10 mol%"),
        ("0.98L", "0.98 L"),
        ("addiertunddieLösung", "addiert und die Lösung"),
        ("vonDiisopropylamin", "von Diisopropylamin"),
        ("wasaddedto the", "was added to the"),
        // 4. Klammer-Verklebungen
        ("(53.8 mmol,1.10 eq)4 addiert", "(53.8 mmol, 1.10 eq) 4 addiert"),
        ("(46.5 mmol,0.95 eq)einer", "(46.5 mmol, 0.95 eq) einer"),
        ("Diisopropylamin(6.55 ml)", "Diisopropylamin (6.55 ml)"),
        // 2. Sonderzeichen für Grad und Minus
        ("0 •C", "0 °C"),
        ("auf–78•C", "auf -78 °C"),
        ("25 ºC", "25 °C"),
        ("25˚C", "25 °C"),
        ("25 ◦C", "25 °C"),
        ("−10 °C", "-10 °C"),
        ("— 78 °C", "-78 °C"),
        ("20 – 25 °C", "20-25 °C"),
        // 3. Silbentrennung
        ("zuge-\ntropft", "zugetropft"),
        ("zuge-tropft", "zugetropft"),
        ("n-Butyllithium-\nLösung", "n-Butyllithium-Lösung"),
        ("tert-\nbutyl", "tert-butyl"),
        ("Pyridin-\n2-yl", "Pyridin-2-yl"),
        ("Zeile eins\nZeile zwei", "Zeile eins Zeile zwei"),
        // Satzgrenzen, Hydrate, Unicode
        ("zugetropft.Nach weiteren", "zugetropft. Nach weiteren"),
        ("CuSO4 · 5 H2O", "CuSO4·5H2O"),
        ("BF3•OEt2", "BF3·OEt2"),
        ("ﬁltriert", "filtriert"),
        ("5 μL", "5 µL"),
        ("6.55\u{00A0}ml", "6.55 ml"),
        ("u\u{0308}ber", "über"),
        // PDF-Schriften, die Grad und Minus als Pfeil liefern (Vertiefungsarbeit)
        ("bei0 →C", "bei 0 °C"),
        ("auf→78→C", "auf -78 °C"),
        // Chemikalienname + Verb verklebt
        ("Diisopropylaminvorgelegtundbei 0 °C", "Diisopropylamin vorgelegt und bei 0 °C"),
        ("THFvorgelegt", "THF vorgelegt"),
        // Nummerierte Überschrift bleibt eigener Absatz, Fließtext-Zeile mit Mengen nicht
        ("5.3.2 Silylketenacetal 5\nIn trockenem THF", "5.3.2 Silylketenacetal 5\n\nIn trockenem THF"),
        ("6.55 ml (46.5 mmol) Diisopropylamin in 40 ml\nTHF vorgelegt", "6.55 ml (46.5 mmol) Diisopropylamin in 40 ml THF vorgelegt"),
    ])
    func repairs(input: String, expected: String) {
        #expect(normalizeSynthesisText(input) == expected)
    }

    @Test("Formeln, Verbindungsnummern und Namen bleiben unverändert", arguments: [
        "Pd(PPh3)4", "Et3N", "K2CO3", "NaBH4", "B2pin2", "Pd2dba3", "Cu(OAc)2", "Ni(cod)2", "CuSO4·5H2O", "Boc2O",
        "CH2Cl2", "H2O", "5CzBN", "3b", "11c", "1a", "3g", "4h", "1,4-Dioxan", "6,55 ml", "N,N-Dimethylformamid",
        "(S)-BINOL", "10% Pd/C", "2-Amino-4-Methyl-Benzoesäuremethylester 6", "tert-Butyl-pyrrolidin-1-carboxylat",
        "Inden", "Undecan", "Indol", "Anilin", "Reaktionslösung", "Natriumsulfatlösung", "Raumtemperatur",
        "Wasserstoffperoxid", "Lösungsmittel", "allylMgBr", "nBuLi", "iPrMgCl·LiCl", "Dess-Martin-Periodinan",
        "[Ir(ppy)2(dtbbpy)]PF6", "1H NMR", "Wassergehalt", "Reaktionsgemisch", "Diisopropylamin", "Dreihalskolben", "Schlenkkolben",
    ])
    func preservesChemistry(text: String) {
        #expect(normalizeSynthesisText(text) == text)
    }

    @Test("Normalisierung ist idempotent")
    func idempotent() {
        let samples = [Self.caseStudyInput, "Absatz eins.\n\nAbsatz zwei mit zuge-\ntropft", "CuSO4 · 5 H2O und 298.0mg"]
        for s in samples {
            let once = normalizeSynthesisText(s)
            #expect(normalizeSynthesisText(once) == once)
        }
    }

    @Test("Absätze bleiben als Satzgrenze erhalten")
    func paragraphs() {
        #expect(normalizeSynthesisText("Satz eins\n\n\nSatz zwei") == "Satz eins\n\nSatz zwei")
    }
}
