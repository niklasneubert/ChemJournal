import AppKit
import CryptoKit

/// Zeichenprogramm für Reaktionsgleichungen.
nonisolated enum DrawingApp: String, CaseIterable, Sendable {
    case chemDraw, reShiki

    /// Einstellungen › Allgemein: welches Programm die Knöpfe bei der Reaktionsgleichung zeigen.
    static let defaultsKey = "drawingApp"

    static var preferred: DrawingApp {
        DrawingApp(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .chemDraw
    }

    var displayName: String { self == .chemDraw ? "ChemDraw" : "ReShiki" }
    var fileExtension: String { self == .chemDraw ? "cdxml" : "rsk" }
    var bundleIdentifier: String { self == .chemDraw ? "com.revvity.ChemDraw" : "dev.reshiki.editor" }
    var other: DrawingApp { self == .chemDraw ? .reShiki : .chemDraw }

    var applicationURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }
    var isInstalled: Bool { applicationURL != nil }
}

/// Hebt die Zeichnung (ChemDraw-CDXML oder ReShiki-RSK) zu einem importierten Reaktionsbild 7 Tage lang auf, damit
/// sie sich noch einmal im Zeichenprogramm öffnen und bearbeiten lässt.
///
/// Die Zeichnung liegt unter `~/Library/Application Support/ChemJournal/ChemDraw-Zeichnungen/`, benannt nach dem
/// SHA-256 des Bildes. So braucht das Journal kein neues Feld: Gehört das Bild noch zur Zeichnung, findet man sie
/// über das Bild. Wird das Bild ersetzt oder entfernt, passt nichts mehr; nach 7 Tagen wird die Datei gelöscht.
nonisolated enum DrawingStore {
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    /// Ordnername aus der Zeit, als es nur ChemDraw gab – bleibt, damit vorhandene Zeichnungen gefunden werden.
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChemJournal/ChemDraw-Zeichnungen", isDirectory: true)
    }

    struct SavedDrawing: Equatable {
        let url: URL
        let expires: Date
        /// Programm, mit dem die Zeichnung entstand – nur dieses kann sie öffnen.
        let app: DrawingApp
    }

    private static func fileURL(for imageData: Data, app: DrawingApp, in directory: URL) -> URL {
        let hash = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + "." + app.fileExtension)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Gespeicherte Zeichnung zu diesem Bild und bis wann sie bearbeitbar ist; `nil`, wenn keine (mehr) da ist.
    static func drawing(for imageData: Data, now: Date = Date(), in directory: URL = directory) -> SavedDrawing? {
        DrawingApp.allCases.compactMap { app -> SavedDrawing? in
            let url = fileURL(for: imageData, app: app, in: directory)
            guard let saved = modificationDate(url) else { return nil }
            let expires = saved.addingTimeInterval(lifetime)
            return expires > now ? SavedDrawing(url: url, expires: expires, app: app) : nil
        }
        .max { $0.expires < $1.expires }
    }

    /// Speichert die Zeichnung zum Bild. Die 7 Tage beginnen mit jedem Speichern neu.
    @discardableResult
    static func save(_ drawing: Data, for imageData: Data, app: DrawingApp = .chemDraw, in directory: URL = directory) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try drawing.write(to: fileURL(for: imageData, app: app, in: directory), options: .atomic)
            // Gleiches Bild aus dem anderen Programm: die neuere Zeichnung gilt
            try? FileManager.default.removeItem(at: fileURL(for: imageData, app: app.other, in: directory))
            return true
        } catch {
            print("Zeichnungen: Speichern fehlgeschlagen: \(error)")
            return false
        }
    }

    /// Löscht Zeichnungen, die älter als 7 Tage sind.
    static func purgeExpired(now: Date = Date(), in directory: URL = directory) {
        let fm = FileManager.default
        let extensions = Set(DrawingApp.allCases.map(\.fileExtension))
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where extensions.contains(file.pathExtension) {
            let saved = modificationDate(file) ?? .distantPast
            if saved.addingTimeInterval(lifetime) <= now { try? fm.removeItem(at: file) }
        }
    }

    /// `true`, wenn die Datei mehr als eine leere Seite enthält (Strukturen, Text, Pfeile, Formen).
    static func containsDrawing(_ data: Data, app: DrawingApp = .chemDraw) -> Bool {
        switch app {
        case .chemDraw:
            let text = String(decoding: data, as: UTF8.self)
            return ["<fragment", "<t ", "<t>", "<graphic", "<arrow", "<group"].contains { text.contains($0) }
        case .reShiki:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
            return ["atoms", "annotations", "arrows", "graphics"].contains { !((json[$0] as? [Any]) ?? []).isEmpty }
        }
    }
}
