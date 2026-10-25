import Foundation
import PDFKit
import Testing
@testable import ChemJournal

@Suite("PDF-Export")
@MainActor
struct PDFExportTests {

    @Test("Namen bleiben Text; nur Summenformeln bekommen tiefgestellte Ziffern")
    func names() {
        #expect(HTMLGenerator.nameHTML("Propionsäure 1") == "Propionsäure 1")
        #expect(HTMLGenerator.nameHTML("CH2Cl2") == "CH<sub>2</sub>Cl<sub>2</sub>")
        #expect(HTMLGenerator.nameHTML("NEt3") == "NEt<sub>3</sub>")
        #expect(HTMLGenerator.nameHTML("Pd(PPh3)4") == "Pd(PPh<sub>3</sub>)<sub>4</sub>")
        #expect(HTMLGenerator.nameHTML("CuSO4·5H2O") == "CuSO<sub>4</sub>·5H<sub>2</sub>O")
        #expect(HTMLGenerator.nameHTML("wfach alles zu3") == "wfach alles zu3")
        #expect(HTMLGenerator.nameHTML("Benzylbromid 2") == "Benzylbromid 2")
        #expect(HTMLGenerator.nameHTML("Name des Produktes\\1") == "Name des Produktes\\1")
        #expect(HTMLGenerator.nameHTML("THF") == "THF")
        #expect(HTMLGenerator.nameHTML("<b>") == "&lt;b&gt;")
    }

    @Test("Ausdrücklich gesetzte Formeln (\\ce, $…$) gehen weiter an MathJax")
    func explicitFormulas() {
        #expect(HTMLGenerator.nameHTML("\\ce{H2O}").contains("$\\ce{H2O}$"))
        #expect(HTMLGenerator.nameHTML("$x^2$") == "$x^2$")
    }

    private func sampleExperiment(stages: Int) -> Experiment {
        var list: [Stage] = []
        for i in 1...stages {
            var s = Stage(title: "Stufe \(i)")
            s.summary = "Veresterung von Propionsäure mit Benzylbromid, \\ce{NEt3} als Base."
            s.chemicals = [
                ChemicalData(name: "wfach alles zu3"),
                ChemicalData(name: "Propionsäure 1", equivalents: "1", amount: "0.13", volume: "10"),
                ChemicalData(name: "CH2Cl2", cas: "75-09-2", molarMass: "84.93", density: "1.3255", volume: "50"),
                ChemicalData(name: "NEt3", equivalents: "1.1", cas: "121-44-8", amount: "0.143", volume: "19.9"),
                ChemicalData(name: "Benzylbromid 2", equivalents: "1.1", cas: "100-39-0", amount: "0.143", volume: "17.1"),
            ]
            s.procedure = String(repeating: "Die Lösung wurde bei $0\\,^\\circ\\mathrm{C}$ gerührt, dann $\\frac{2}{3}$ des Lösungsmittels entfernt und mit \\ce{NH3} versetzt. ", count: 6)
            s.observation = "Farbumschlag nach gelb."
            s.yieldProducts = [
                YieldData(name: "Name des Produktes mit einem sehr langen Namen\\1", molarMass: "53", mass: "6.278"),
                YieldData(name: "\\ce{}", molarMass: "90", mass: "180"),
            ]
            list.append(s)
        }
        return Experiment(title: "Benzylpropionat", summary: "Testansatz für den PDF-Export", stages: list)
    }

    @Test("A4-Seiten mit automatischem Umbruch und Seitenzahlen")
    func paginatedPDF() async throws {
        let html = HTMLGenerator.generate(for: [sampleExperiment(stages: 4)], projectName: "Ester")
        let data: Data? = await withCheckedContinuation { cont in
            PDFManager.shared.generatePDF(from: html, footer: "Ester") { cont.resume(returning: $0) }
        }
        let pdf = try #require(data.flatMap(PDFDocument.init(data:)))
        #expect(pdf.pageCount >= 2)
        let first = try #require(pdf.page(at: 0))
        #expect(abs(first.bounds(for: .mediaBox).height - 841.89) < 1)   // A4
        #expect(first.string?.contains("Seite 1 von \(pdf.pageCount)") == true)
        #expect(pdf.string?.contains("Propionsäure 1") == true)
        // Zum Ansehen
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("ChemJournal-PDFExportTest.pdf")
        try data?.write(to: out)
        print("PDF-TEST-AUSGABE: \(out.path)")
    }
}
