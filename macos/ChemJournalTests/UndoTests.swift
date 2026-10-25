import Foundation
import Testing
@testable import ChemJournal

@Suite("Widerrufen (⌘Z)")
@MainActor
struct UndoTests {

    private func storeWithExperiment() -> JournalStore {
        let store = JournalStore(inMemory: true)
        var stage = Stage(title: "Stufe 1")
        stage.chemicals = [ChemicalData(name: "THF")]
        store.projects = [Project(title: "P", experiments: [Experiment(title: "Ansatz", summary: "", stages: [stage])])]
        return store
    }

    @Test("Gelöschte Zeile kommt mit ⌘Z zurück, ⇧⌘Z löscht sie wieder")
    func undoDeletion() {
        let store = storeWithExperiment()
        store.projects[0].experiments[0].stages[0].chemicals.removeAll()
        #expect(store.projects[0].experiments[0].stages[0].chemicals.isEmpty)

        #expect(store.undo())
        #expect(store.projects[0].experiments[0].stages[0].chemicals.map(\.name) == ["THF"])
        #expect(store.redo())
        #expect(store.projects[0].experiments[0].stages[0].chemicals.isEmpty)
    }

    @Test("Schnelles Tippen ist ein Schritt – getrennt vom vorherigen Anlegen")
    func typingIsGrouped() async throws {
        let store = storeWithExperiment()
        try await Task.sleep(for: .milliseconds(350))   // Nutzer klickt ins Feld
        for title in ["A", "An", "Ans", "Ansa"] { store.projects[0].experiments[0].title = title }
        #expect(store.undo())
        #expect(store.projects.first?.experiments.first?.title == "Ansatz")
    }

    @Test("Gelöschter Ansatz kommt zurück")
    func undoExperimentDeletion() {
        let store = storeWithExperiment()
        store.projects[0].experiments.removeAll()
        #expect(store.undo())
        #expect(store.projects[0].experiments.map(\.title) == ["Ansatz"])
    }

    @Test("Neue Änderung nach ⌘Z verwirft „Wiederholen“")
    func newEditClearsRedo() {
        let store = storeWithExperiment()
        store.projects[0].experiments[0].stages.append(Stage(title: "Stufe 2"))
        #expect(store.undo())
        store.projects[0].experiments[0].stages[0].title = "Neu"
        #expect(!store.canRedo)
        #expect(!store.redo())
    }

    @Test("Nichts zu widerrufen: kein Absturz, Rückgabe false")
    func emptyStack() {
        let store = JournalStore(inMemory: true)
        #expect(!store.undo())
        #expect(!store.redo())
    }

    @Test("Höchstzahl gemerkter Schritte wird eingehalten")
    func limit() {
        let store = JournalStore(inMemory: true)
        for i in 0..<(JournalStore.undoLimit + 20) { store.projects.append(Project(title: "P\(i)")) }
        var steps = 0
        while store.undo() { steps += 1 }
        #expect(steps == JournalStore.undoLimit)
    }
}
