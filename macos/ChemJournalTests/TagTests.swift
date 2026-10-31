import Foundation
import Testing
@testable import ChemJournal

@Suite("Markierung und Tags")
struct TagTests {
    private func experiment(_ title: String, tags: [String] = [], marked: Bool = false) -> Experiment {
        var e = Experiment(title: title, summary: "")
        e.tags = tags; e.isMarked = marked
        return e
    }

    @Test("Tag-Namen werden bereinigt, Dubletten ignoriert (Groß-/Kleinschreibung egal)")
    func addTags() {
        var e = experiment("A")
        let added = e.addTag("  #Photo   katalyse ")
        #expect(added)
        #expect(e.tags == ["Photo katalyse"])
        let duplicate = e.addTag("photo KATALYSE"), blank = e.addTag("   "), hashOnly = e.addTag("#")
        #expect(!duplicate && !blank && !hashOnly)
        #expect(e.tags == ["Photo katalyse"])
        e.removeTag("PHOTO katalyse")
        #expect(e.tags.isEmpty)
    }

    @Test("Ältere Journale ohne Markierung und Tags laden weiter; beides wird gespeichert")
    func decoding() throws {
        var e = experiment("Alt")
        let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as! [String: Any]
        var stripped = old; stripped["isMarked"] = nil; stripped["tags"] = nil
        let loaded = try JSONDecoder().decode(Experiment.self, from: JSONSerialization.data(withJSONObject: stripped))
        #expect(loaded.isMarked == false && loaded.tags.isEmpty && loaded.title == "Alt")

        e.isMarked = true; e.tags = ["Scale-up"]
        let round = try JSONDecoder().decode(Experiment.self, from: JSONEncoder().encode(e))
        #expect(round.isMarked && round.tags == ["Scale-up"])
    }

    @Test("Fremde JSON-Datei wird beim Import weiter abgelehnt")
    func rejectsForeign() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Experiment.self, from: Data(#"{"name":"x"}"#.utf8)) }
    }

    @Test("Alle Tags im Journal, umbenennen und löschen")
    func renameAndDelete() {
        var projects = [Project(title: "P", experiments: [
            experiment("1", tags: ["Scale-up", "NMR"]),
            experiment("2", tags: ["scale-up"]),
            experiment("3", tags: ["Grosser Ansatz", "Scale-up"]),
        ])]
        #expect(JournalTag.all(in: projects) == ["Grosser Ansatz", "NMR", "Scale-up"])

        JournalTag.rename("SCALE-UP", to: "Grosser Ansatz", in: &projects)
        #expect(projects[0].experiments.map(\.tags) == [["Grosser Ansatz", "NMR"], ["Grosser Ansatz"], ["Grosser Ansatz"]])

        JournalTag.rename("nmr", to: "NMR-Probe", in: &projects)
        #expect(projects[0].experiments[0].tags == ["Grosser Ansatz", "NMR-Probe"])

        JournalTag.delete("grosser ansatz", in: &projects)
        #expect(projects[0].experiments.map(\.tags) == [["NMR-Probe"], [], []])
    }

    @Test("Suche findet Tags, auch mit #")
    func search() {
        let projects = [Project(title: "P", experiments: [experiment("Suzuki", tags: ["Scale-up"]), experiment("Heck")])]
        for query in ["scale", "#scale-up", "#Scale"] {
            let s = JournalSearch(query: query, projects: projects)
            #expect(s.hits(in: projects[0].experiments[0]) != nil, "\(query)")
            #expect(s.hits(in: projects[0].experiments[1]) == nil, "\(query)")
        }
    }
}
