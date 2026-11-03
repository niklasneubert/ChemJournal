import Testing
@testable import ChemJournal

@Suite("Tag-Farben")
@MainActor
struct TagColorTests {
    @Test("Gleiche Farbe wie unter Linux (src/shared/tags.js), unabhängig von Groß-/Kleinschreibung")
    func sameAsLinux() {
        #expect(["Photokatalyse", "Kreuzkupplung", "TADF", "Scale-up", "Grignard", "Praktikum"].map(TagColor.name(for:))
                == ["teal", "lavender", "teal", "gold", "purple", "purple"])
        #expect(TagColor.name(for: "photokatalyse") == TagColor.name(for: "Photokatalyse"))
    }
}
