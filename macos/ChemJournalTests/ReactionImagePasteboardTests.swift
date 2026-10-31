import AppKit
import Testing
@testable import ChemJournal

@Suite("Reaktionsbild kopieren und einfügen")
struct ReactionImagePasteboardTests {
    /// Eigene Zwischenablage – die des Nutzers bleibt unberührt.
    private func pasteboard() -> NSPasteboard { NSPasteboard(name: .init("ChemJournalTest-\(UUID().uuidString)")) }

    private func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test("Einfügen ergibt genau dieselben Bytes – die ChemDraw-Zeichnung bleibt zugeordnet")
    func roundTrip() {
        let pb = pasteboard(); defer { pb.releaseGlobally() }
        let data = png()
        ReactionImagePasteboard.write(data, to: pb)
        #expect(ReactionImagePasteboard.read(from: pb) == data)
        #expect(pb.data(forType: .png) != nil && pb.data(forType: .tiff) != nil)
    }

    @Test("Bild aus einem anderen Programm (nur TIFF) wird als PNG eingefügt")
    func foreignTIFF() throws {
        let pb = pasteboard(); defer { pb.releaseGlobally() }
        let tiff = try #require(NSImage(data: png())?.tiffRepresentation)
        pb.clearContents(); pb.setData(tiff, forType: .tiff)
        let pasted = try #require(ReactionImagePasteboard.read(from: pb))
        #expect(pasted.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("Leere Zwischenablage oder nur Text: nichts einfügen")
    func nothing() {
        let pb = pasteboard(); defer { pb.releaseGlobally() }
        pb.clearContents(); pb.setString("Hallo", forType: .string)
        #expect(ReactionImagePasteboard.read(from: pb) == nil)
    }
}
