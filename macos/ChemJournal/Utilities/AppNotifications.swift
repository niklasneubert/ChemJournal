import Foundation

/// Menübefehle aus `MyApp` an die Ansichten. Vorher als lose Strings verteilt.
extension Notification.Name {
    static let newExperiment = Notification.Name("NeuerAnsatz")
    static let newProject = Notification.Name("NeuesProjekt")
    static let saveJournal = Notification.Name("Speichern")
    static let exportPDF = Notification.Name("ExportPDF")
    static let importChemjournal = Notification.Name("ImportChemjournal")
    static let importFromChemDraw = Notification.Name("ImportFromChemDraw")
    static let snapToOptimalWidth = Notification.Name("SnapToOptimalWidth")
    /// `object`: UUID des Ansatzes, der in der Seitenleiste ausgewählt werden soll.
    static let selectExperiment = Notification.Name("SelectExperiment")
}
