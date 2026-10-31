import Foundation
import Testing
@testable import ChemJournal

@Suite("Verbindungsnummern fett")
struct CompoundNumberTests {
    @Test("(1), (12) und (2a) werden fett, die Klammern fallen weg")
    func bold() {
        let html = LaTeXEditorView.previewHTML("Carbazol (1) und Nitril (2a) ergaben (12).", boldCompoundNumbers: true)
        #expect(html == "Carbazol <b>1</b> und Nitril <b>2a</b> ergaben <b>12</b>.")
    }

    @Test("Mengen, Zeiten und Prozente in Klammern bleiben normal")
    func notNumbers() {
        let text = "THF (5 mL), 2 h (95%), (1.5 mmol), (4R), (1234)"
        #expect(LaTeXEditorView.previewHTML(text, boldCompoundNumbers: true) == LaTeXEditorView.previewHTML(text))
        #expect(!LaTeXEditorView.containsCompoundNumbers(text))
    }

    @Test("Formeln bleiben unangetastet")
    func formulas() {
        let html = LaTeXEditorView.previewHTML("$f(1)$ und \\ce{A (1)} mit (3)", boldCompoundNumbers: true)
        #expect(html == "$f(1)$ und $\\ce{A (1)}$ mit <b>3</b>")
    }

    @Test("Ohne Schalter (Zusammenfassung) bleibt alles wie bisher")
    func offByDefault() {
        #expect(LaTeXEditorView.previewHTML("Produkt (1)") == "Produkt (1)")
    }
}

@Suite("ChemDraw-Zeichnungen 7 Tage aufheben")
struct DrawingStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ChemDrawStoreTest-\(UUID().uuidString)", isDirectory: true)
    }

    private let drawing = Data("<CDXML><page><fragment id=\"1\"/></page></CDXML>".utf8)

    @Test("Gespeicherte Zeichnung gehört zum Bild und ist 7 Tage bearbeitbar")
    func saveAndFind() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let image = Data([1, 2, 3, 4])
        #expect(DrawingStore.save(drawing, for: image, in: dir))
        let found = try #require(DrawingStore.drawing(for: image, in: dir))
        #expect(try Data(contentsOf: found.url) == drawing)
        #expect(abs(found.expires.timeIntervalSinceNow - 7 * 24 * 3600) < 60)
        // Anderes Bild (ersetzt oder per Drag & Drop) hat keine Zeichnung
        #expect(DrawingStore.drawing(for: Data([9]), in: dir) == nil)
    }

    @Test("Nach 7 Tagen nicht mehr bearbeitbar und gelöscht")
    func expiry() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let image = Data([5, 6])
        DrawingStore.save(drawing, for: image, in: dir)
        let later = Date().addingTimeInterval(7 * 24 * 3600 + 1)
        #expect(DrawingStore.drawing(for: image, now: later, in: dir) == nil)
        DrawingStore.purgeExpired(now: Date().addingTimeInterval(6 * 24 * 3600), in: dir)
        #expect(DrawingStore.drawing(for: image, in: dir) != nil)
        DrawingStore.purgeExpired(now: later, in: dir)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == true)
    }

    @Test("ReShiki-Zeichnung: eigenes Format, gehört zum Bild, ersetzt eine ChemDraw-Zeichnung zum selben Bild")
    func reShiki() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let image = Data([7, 7, 7])
        let rsk = Data(#"{"version":29,"atoms":[{"id":1}],"bonds":[],"annotations":[],"arrows":[],"graphics":[]}"#.utf8)
        #expect(DrawingStore.containsDrawing(rsk, app: .reShiki))
        #expect(!DrawingStore.containsDrawing(Data(ReShikiBridge.emptyDocument.utf8), app: .reShiki))
        DrawingStore.save(drawing, for: image, app: .chemDraw, in: dir)
        DrawingStore.save(rsk, for: image, app: .reShiki, in: dir)
        let found = try #require(DrawingStore.drawing(for: image, in: dir))
        #expect(found.app == .reShiki && found.url.pathExtension == "rsk")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.count == 1)
    }

    @Test("Leere Seite zählt nicht als Zeichnung, die Querformat-Vorlage ist leer")
    func emptyPage() {
        #expect(DrawingStore.containsDrawing(drawing))
        #expect(!DrawingStore.containsDrawing(Data(ChemDrawBridge.landscapeTemplate.utf8)))
        #expect(ChemDrawBridge.landscapeTemplate.contains("BoundingBox=\"0 0 769.86 523.26\""))
    }
}
