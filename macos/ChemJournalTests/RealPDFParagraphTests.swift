import Testing
@testable import ChemJournal

/// Echte Absätze, so wie PDFKit sie beim Kopieren liefert (inkl. Artefakten wie "→" statt "°" und "−").
@Suite("Smart Extract – echte PDF-Absätze")
struct RealPDFParagraphTests {

    /// Vertiefungsarbeit N. Neubert, Abschnitt 5.3.2 (Kopie aus PDFKit)
    static let thesis = #"""
    5.3.2 Propionsäurebenzylester-Silylketenacetal 5
    In trockenem THF wurden 3.39 g (1.1eq, 33.5mmol)Diisopropylaminvorgelegtundbei0 →C
    2.15 g (1.1eq, 33.5mmol) n-BuLi zugegeben. Nach 15 Minuten rühren wurde die Lösung auf
    →78→C abgekühlt und 5.00 g (1.0eq, 30.5mmol) des Propionsäurebenzylesters 3 langsam ad-
    diert. Die Lösung wurde anschließend für 30 Minuten bei→78→C gerührt. Als Letztes wurde
    3.97 g (1.20 eq, 36.5mmol)Trimethylsilylchlorid4 zugegeben und die Lösung für 2 Stunden
    auf Raumtemperatur erwärmt. Das Lösungsmittel wurde unter vermindertem Druck entfernt
    und das Rohprodukt anschließened in 50 ml n-Pentan gelöst. Es wurde mit dest. Wasser,
    gesättigter NaHCO3-Lösung und gesättigter NaCl-Lösung gewaschen. Die organische Phase
    wurde mit Na2SO4 getrocknet und das Lösungsmittel im Vakuum entfernt. Zur Aufreinigung
    wurde eine Vakuumdestillation durchgeführt und 1.22 g (5.16 mmol, 17.0%) des Produktes
    5 als leicht gelbliche Flüssigkeit erhalten.
    Mithilfe des 1H-NMR-Spektrums konnte ein E/Z-Verhältnis von↑ 3:1bestimmt werden.
    Ausbeute: 1.22 g;leichtgelblicheFlüssigkeit.
    1H-NMR (400 Mhz, CDCl3): ω [ppm] = 0.19 (s, 9H, Si→(CH3)3), 1.50 (d, 3H, CH3), 3.72
    (q, 1H, CH), 4.83 (s, 2H, Ar→CH2), 7.25-7.40 (m, 5H, Ar→H).
    5.3.3 ε-Trimethylsilyl-Propionsäurebenzylester 6
    41
    """#

    /// Absatz im Stil einer Supporting Information (eigene Umformulierung; Mengen und PDF-Artefakte wie im Original,
    /// z. B. "-hydroxyketone" ohne α und Zeilenumbrüche mitten in Mengenangaben)
    static let supportingInformation = #"""
    6. General procedures
    Microwave-assisted cleavage of the -hydroxyketone (1): A 5-mL microwave vial was loaded with
    9(10)-hydroxy-10(9)-oxooctadecanoate 1 (1:1 mixture of
    regioisomers) (65.7 mg, 0.2 mmol, 1 equiv), the thiazolium salt (0.04 mmol, 20 mol%) and K2CO3 (5.5
    mg, 0.04 mmol, 20 mol%). After flushing with argon, dry CH3CN (2 mL) was
    added. The vial was heated in the microwave reactor at the chosen temperature for the given
    time. After cooling to room temperature the conversion was determined by GC (hexadecane as
    internal standard).
    Cleavage with recovery of the aldehydes by distillation: In a 25-mL round-bottom flask under argon,
    K2CO3 (1.09 mmol,
    150.6 mg, 9 mol%) and 3,4,5-trimethylthiazol-3-ium iodide 11 (309.0 mg, 1.21 mmol, 10 mol%) were
    dissolved in dry CH3CN (4 mL). After stirring for 10 minutes at room temperature, the yellow solution
    was taken up with a syringe and injected into a distillation flask holding the starting material 1 (4.00 g, 12.18 mmol). The
    17
    """#

    @Test("Vertiefungsarbeit: verklebte Wörter, Pfeile als Grad/Minus, Silbentrennung")
    func thesisParagraph() {
        let rows = SmartExtractor(model: nil).extract(from: Self.thesis).map { [$0.name, $0.equivalents, $0.amount, $0.mass] }
        #expect(rows == [
            ["THF", "", "", ""],
            ["Diisopropylamin", "1.1", "0.0335", "3.39"],
            ["n-BuLi", "1.1", "0.0335", "2.15"],
            ["Propionsäurebenzylesters 3", "1", "0.0305", "5"],
            ["Trimethylsilylchlorid 4", "1.2", "0.0365", "3.97"],
        ])
    }

    @Test("Supporting Information: Einschübe, mol%, Verbindungsnummern")
    func supportingInformationParagraph() {
        let rows = SmartExtractor(model: nil).extract(from: Self.supportingInformation).map { [$0.name, $0.equivalents, $0.amount, $0.volume, $0.mass] }
        #expect(rows == [
            ["9(10)-hydroxy-10(9)-oxooctadecanoate 1", "1", "0.0002", "", "0.0657"],
            ["thiazolium salt", "0.2", "0.00004", "", ""],
            ["K2CO3", "0.2", "0.00004", "", "0.0055"],
            ["CH3CN", "", "", "2", ""],
            ["K2CO3", "0.09", "0.00109", "", "0.151"],
            ["3,4,5-trimethylthiazol-3-ium iodide 11", "0.1", "0.00121", "", "0.309"],
            ["CH3CN", "", "", "4", ""],
            ["starting material 1", "", "0.0122", "", "4"],
        ])
    }

    @Test("Mit eingebettetem Modell ergibt die Vertiefungsarbeit dieselben Zeilen")
    func thesisWithModel() async {
        let rows = await SmartExtractService.shared.extract(from: Self.thesis).map { [$0.name, $0.equivalents, $0.amount, $0.mass] }
        #expect(rows.contains(["Diisopropylamin", "1.1", "0.0335", "3.39"]))
        #expect(rows.contains(["Trimethylsilylchlorid 4", "1.2", "0.0365", "3.97"]))
    }
}
