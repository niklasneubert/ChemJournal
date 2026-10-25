import Foundation
import Testing
@testable import ChemJournal

@Suite("Zahlenformat")
struct NumberFormattingTests {
    @Test func fixedDecimals() {
        #expect(format3(6.55) == "6.55")
        #expect(format3(1234.5678) == "1234.568")
        #expect(format4(0.0465) == "0.0465")
        #expect(format4(1.1) == "1.1")
    }

    @Test("Kleine Werte behalten signifikante Stellen (vorher 115 µmol → \"0\")")
    func smallValues() {
        #expect(format4(0.000115) == "0.000115")
        #expect(format3(0.0298) == "0.0298")
        #expect(format3(0) == "0")
    }

    @Test func parsing() {
        #expect(parseDecimal("6,55") == 6.55)
        #expect(parseDecimal("6.55") == 6.55)
        #expect(parseDecimal(".5") == 0.5)
        #expect(parseDecimal("1e5") == nil)
        #expect(parseDecimal("") == nil)
        #expect(parseDecimal("abc") == nil)
    }
}

@Suite("Datenspeicher")
struct JournalPersistenceTests {

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ChemJournalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Speichern und Laden ergibt denselben Inhalt")
    func roundTrip() async throws {
        let dir = try makeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = JournalPersistence(directory: dir)
        let projects = [Project(title: "Test", experiments: [Experiment(title: "A", summary: "B")])]
        persistence.saveAndWait(projects)
        guard case .loaded(let loaded) = await persistence.load() else { Issue.record("nicht geladen"); return }
        #expect(loaded == projects)
    }

    @Test("Beschädigte Datei: Backup wird geladen, Original gesichert, Backup nicht überschrieben")
    func corruptFileRecovery() async throws {
        let dir = try makeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let good = [Project(title: "Gut")]
        try JSONEncoder().encode(good).write(to: dir.appendingPathComponent("ChemJournalData.bak.json"))
        try Data("{kaputt".utf8).write(to: dir.appendingPathComponent("ChemJournalData.json"))

        let persistence = JournalPersistence(directory: dir)
        guard case .recoveredFromBackup(let recovered, let preserved) = await persistence.load() else {
            Issue.record("Backup wurde nicht verwendet"); return
        }
        #expect(recovered == good)
        #expect(FileManager.default.fileExists(atPath: preserved.path))

        // Erster Speichervorgang darf das gute Backup nicht durch die kaputte Datei ersetzen
        persistence.saveAndWait([Project(title: "Neu")])
        let backup = try JSONDecoder().decode([Project].self, from: Data(contentsOf: dir.appendingPathComponent("ChemJournalData.bak.json")))
        #expect(backup == good)
    }

    @Test("Store im Testmodus schreibt keine Dateien")
    func inMemoryStore() {
        let store = JournalStore(inMemory: true)
        store.projects.append(Project(title: "X"))
        #expect(store.isLoaded)
        #expect(store.projects.count == 1)
    }
}
