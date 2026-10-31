import Foundation
import Testing
@testable import ChemJournal

@Suite("Aufreinigung & Analytik")
struct AnalysisTests {
    private func stageJSON(_ extra: String) -> Data {
        Data("""
        {"id":"\(UUID().uuidString)","title":"Stufe 1","sourceURL":"","summary":"","procedure":"","observation":"",
         "chemicals":[],"yieldProducts":[],"isExpanded":true,"createdAt":700000000\(extra)}
        """.utf8)
    }

    @Test("Alte Dateilisten werden zu Einträgen mit erratener Methode")
    func migration() throws {
        let old = #","analysisFiles":[{"id":"\#(UUID().uuidString)","filePath":"/x/NK12_1H.fid","description":"1H NMR CDCl3"},"# +
            #"{"id":"\#(UUID().uuidString)","filePath":"/x/NK12_13C.pdf","description":""},"# +
            #"{"id":"\#(UUID().uuidString)","filePath":"/x/hrms_esi.pdf","description":"HRMS"},"# +
            #"{"id":"\#(UUID().uuidString)","filePath":"/x/foto.jpg","description":"Kristalle"}]"#
        let stage = try JSONDecoder().decode(Stage.self, from: stageJSON(old))
        #expect(stage.analyses.map(\.method) == [.nmr, .nmr, .ms, .other])
        #expect(stage.analyses.map(\.heading) == ["¹H-NMR", "¹³C{¹H}-NMR", "HRMS", "Sonstiges"])
        #expect(stage.analysisFiles.map(\.filePath) == ["/x/NK12_1H.fid", "/x/NK12_13C.pdf", "/x/hrms_esi.pdf", "/x/foto.jpg"])
        #expect(stage.analyses[0].files[0].description == "1H NMR CDCl3")
    }

    @Test("Ohne Analysen und ohne Dateiliste: leer")
    func empty() throws {
        #expect(try JSONDecoder().decode(Stage.self, from: stageJSON("")).analyses.isEmpty)
    }

    @Test("Speichern: Einträge und zusätzlich die flache Dateiliste (für ältere Versionen und Linux)")
    func roundTrip() throws {
        var nmr = AnalysisEntry(method: .nmr, sample: "Produkt 3", values: ["nucleus": "¹H", "solvent": "CDCl₃"])
        nmr.files = [AnalysisFile(filePath: "/x/1H.fid", description: "Rohdaten")]
        let stage = Stage(title: "S", analyses: [nmr, AnalysisEntry(method: .column, values: ["eluent": "PE/EtOAc 10:1"])])
        let data = try JSONEncoder().encode(stage)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect((json["analysisFiles"] as? [[String: Any]])?.first?["filePath"] as? String == "/x/1H.fid")
        let loaded = try JSONDecoder().decode(Stage.self, from: data)
        #expect(loaded.analyses == stage.analyses)
    }

    @Test("Unbekannte Methode aus einer neueren Version wird „Sonstiges“")
    func unknownMethod() throws {
        let e = try JSONDecoder().decode(AnalysisEntry.self, from: Data(#"{"method":"raman","values":{"notes":"x"}}"#.utf8))
        #expect(e.method == .other && e.value("notes") == "x")
    }

    @Test("NMR-Zeile wie in der Experimentalbeschreibung")
    func nmrSummary() {
        let e = AnalysisEntry(method: .nmr, values: ["nucleus": "¹H", "frequency": "400", "solvent": "CDCl₃", "sampleMass": "12",
                                                    "data": "7.26 (d, J = 8.0 Hz, 2H)"])
        #expect(e.summary == "¹H-NMR (400 MHz, CDCl₃, 12 mg): δ = 7.26 (d, J = 8.0 Hz, 2H)")
    }

    @Test("MS: Massenabweichung in ppm")
    func msDeviation() {
        let e = AnalysisEntry(method: .ms, values: ["kind": "HRMS", "ionization": "ESI", "ion": "[M+H]⁺", "formula": "C20H13F4N2",
                                                   "mzCalc": "345.1015", "mzFound": "345.1012"])
        #expect(e.results.first?.value == "Δ = −0.9 ppm")
        #expect(e.summary == "HRMS (ESI): m/z [M+H]⁺ ber. für C20H13F4N2: 345.1015, gef.: 345.1012 (Δ = −0.9 ppm)")
    }

    @Test("Säule und Umkristallisation: Wiederfindung; UV/Vis: ε")
    func computed() {
        let column = AnalysisEntry(method: .column, values: ["crudeMass": "250", "isolatedMass": "180"])
        #expect(column.results.first?.value == "72 %")
        let recryst = AnalysisEntry(method: .recrystallization, values: ["crudeMass": "500", "crystalMass": "410"])
        #expect(recryst.results.first?.value == "82 %")
        let uv = AnalysisEntry(method: .uvVis, values: ["concentration": "1e-5", "absorbance": "0.45", "lambdaMax": "350"])
        #expect(uv.results.first?.value == "ε = 45 000 L·mol⁻¹·cm⁻¹")
        #expect(uv.summary.contains("λmax = 350 nm (ε = 45 000"))
    }

    @Test("Jede Methode hat Felder mit eindeutigen Schlüsseln")
    func fieldsUnique() {
        for m in AnalysisMethod.allCases {
            let keys = m.fields.map(\.key)
            #expect(!keys.isEmpty && Set(keys).count == keys.count, "\(m)")
            #expect(Set(m.inheritedKeys).isSubset(of: Set(keys)), "\(m)")
        }
    }

    @Test("Suche findet Lösungsmittel und Eluent aus Aufreinigung & Analytik")
    func search() {
        var exp = Experiment(title: "A", summary: "")
        exp.stages = [Stage(title: "S", analyses: [AnalysisEntry(method: .column, values: ["eluent": "PE/EtOAc 10:1"])])]
        let projects = [Project(title: "P", experiments: [exp])]
        #expect(JournalSearch(query: "etoac", projects: projects).hits(in: exp) != nil)
        #expect(JournalSearch(query: "säulenchromatographie", projects: projects).hits(in: exp) != nil)
        #expect(JournalSearch(query: "cdcl3", projects: projects).hits(in: exp) == nil)
    }

    @Test("PDF enthält Aufreinigung & Analytik")
    func pdf() {
        var exp = Experiment(title: "A", summary: "")
        exp.stages = [Stage(title: "S", analyses: [AnalysisEntry(method: .nmr, sample: "Produkt 3", values: ["nucleus": "¹H", "solvent": "CDCl₃"])])]
        let html = HTMLGenerator.generate(for: [exp], projectName: "P")
        #expect(html.contains("<b>¹H-NMR</b> – Produkt 3 (CDCl₃)"))
        #expect(html.contains("Aufreinigung &amp; Analytik") || html.contains("Aufreinigung & Analytik"))
    }

    @Test("NMR mit mehreren Kernen in einer Datei, mit Anmerkungen")
    func multiNucleus() {
        let e = AnalysisEntry(method: .nmr, values: ["nucleus": "¹H, ¹³C{¹H}, HSQC", "frequency": "400", "solvent": "CDCl₃",
                                                    "notes": "Rohspektrum"])
        #expect(e.heading == "¹H/¹³C{¹H}-NMR, HSQC")
        #expect(e.summary == "¹H/¹³C{¹H}-NMR, HSQC (400 MHz, CDCl₃). Rohspektrum")
        #expect(AnalysisEntry(method: .nmr, values: ["nucleus": "COSY"]).heading == "COSY")
        #expect(AnalysisMethod.nmr.fields.contains { $0.key == "notes" })
    }

    @Test("Drehwert: [α] aus α, c und l, optische Reinheit, Literaturschreibweise")
    func opticalRotation() {
        let e = AnalysisEntry(method: .opticalRotation, values: ["measured": "+0.253", "concentration": "1.00", "pathLength": "1",
                                                                "wavelength": "589 nm (Na-D)", "temperature": "20", "solvent": "CHCl₃",
                                                                "literature": "+26.0"])
        #expect(e.results.map(\.value) == ["[α] = +25.3", "97 %"])
        #expect(e.summary == "Drehwert: [α]D²⁰ = +25.3 (c 1.00, CHCl₃); Literatur: +26.0; optische Reinheit 97 %")
        // Direkt abgelesener Wert, andere Wellenlänge, negatives Vorzeichen
        let f = AnalysisEntry(method: .opticalRotation, values: ["specific": "−12.4", "wavelength": "546 nm (Hg)", "temperature": "25"])
        #expect(f.summary == "Drehwert: [α]₅₄₆²⁵ = −12.4")
        #expect(AnalysisGroup.other.methods.contains(.opticalRotation))
    }

    @Test("Spektroskopie-Methoden heißen …-Spektroskopie, Überschriften bleiben kurz")
    func spectroscopyNames() {
        #expect(AnalysisMethod.nmr.title == "NMR-Spektroskopie" && AnalysisMethod.ir.title == "IR-Spektroskopie")
        #expect(AnalysisMethod.uvVis.title == "UV/Vis-Spektroskopie")
        #expect(AnalysisEntry(method: .ir, values: ["technique": "ATR"]).summary == "IR (ATR)")
        #expect(AnalysisEntry(method: .uvVis).heading == "UV/Vis" && AnalysisEntry(method: .nmr).heading == "NMR")
    }

    @Test("EPR: Messbedingungen und Ergebnisse wie im Experimentalteil")
    func epr() {
        let e = AnalysisEntry(method: .epr, values: ["technique": "CW-EPR", "band": "X-Band (~9.5 GHz)", "frequency": "9.48",
                                                    "power": "2", "modAmp": "0.2", "modFreq": "100", "temperature": "77",
                                                    "sampleState": "gefrorene Lösung", "solvent": "Toluol",
                                                    "gValues": "2.0034", "hyperfine": "A(¹⁴N) = 42 MHz", "simulation": "EasySpin"])
        #expect(e.heading == "CW-EPR")
        #expect(e.summary == "CW-EPR (X-Band, 9.48 GHz, 2 mW, Mod. 0.2 mT/100 kHz, 77 K, gefrorene Lösung, Toluol): g = 2.0034; A(¹⁴N) = 42 MHz; Simulation: EasySpin")
        #expect(AnalysisEntry(method: .epr).heading == "EPR")
        #expect(AnalysisEntry(method: .epr, values: ["technique": "Puls-EPR (ESE)"]).heading == "Puls-EPR")
        #expect(AnalysisGroup.spectroscopy.methods.contains(.epr))
    }

    @Test("DC ohne Platte, Säule heißt (LC), XRD")
    func methodChanges() {
        #expect(!AnalysisMethod.tlc.fields.contains { $0.key == "plate" })
        #expect(AnalysisMethod.column.title == "Säulenchromatographie (LC)")
        let x = AnalysisEntry(method: .xrd, values: ["kind": "Einkristall (SC-XRD)", "spaceGroup": "P2₁/c", "ccdc": "2345678"])
        #expect(x.heading == "SC-XRD")
        #expect(x.summary.contains("Raumgruppe P2₁/c") && x.summary.contains("CCDC-Nummer 2345678"))
        #expect(AnalysisEntry(method: .xrd, values: ["kind": "Pulver (PXRD)"]).heading == "PXRD")
        #expect(AnalysisGroup.allCases.first == .purification)
    }
}
