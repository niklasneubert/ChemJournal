import CoreML
import Foundation
import NaturalLanguage

/// Führt Smart Extract im Hintergrund aus. Das Modell wird einmal geladen und wiederverwendet;
/// vorher wurde es bei jedem Klick auf "Extrahieren" auf dem Main-Thread neu geladen.
actor SmartExtractService {
    static let shared = SmartExtractService()

    /// Modelle, die die App lädt (erstes vorhandenes gewinnt). Ältere Modelle liegen nur noch im Ordner
    /// "Training model for image classification". Fehlt jedes Modell, arbeitet Smart Extract rein regelbasiert.
    static let candidateModels = [
        "Smart Extract for ChemJournal 15",   // trainiert auf Datensatz v2 (dataset_builder.py, 2026-10-23)
    ]

    private var model: NLModel?
    private(set) var loadedModelName: String?
    private var didLoad = false

    func extract(from text: String) -> [ChemicalData] {
        loadModelIfNeeded()
        return SmartExtractor(model: model).extract(from: text)
    }

    /// Lädt das Modell vorab (z. B. beim Öffnen des Dialogs), damit der erste Klick schnell ist.
    func warmUp() { loadModelIfNeeded() }

    private func loadModelIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        for name in Self.candidateModels {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { continue }
            do {
                let mlModel = try MLModel(contentsOf: url)
                model = try NLModel(mlModel: mlModel)
                loadedModelName = name
                return
            } catch {
                print("Smart Extract: \(name) konnte nicht geladen werden: \(error)")
            }
        }
        print("Smart Extract: kein Modell gefunden – nur regelbasierte Extraktion.")
    }
}
