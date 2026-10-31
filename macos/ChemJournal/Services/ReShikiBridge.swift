import AppKit

/// Zeichnen in ReShiki (quelloffen, reshiki.com) statt ChemDraw.
///
/// Ablauf wie bei ChemDraw: ChemJournal legt eine `.rsk`-Datei an (leer oder die gespeicherte Zeichnung) und öffnet
/// sie in ReShiki. ⌘S in ReShiki sichert die Datei; ChemJournal rendert sie über ReShikis Kommandozeile
/// (`reshiki --cli render`) zu einem PNG, übernimmt es und beendet den Modus. ReShiki sichert Entwürfe getrennt, die
/// Datei ändert sich also nur beim Sichern.
///
/// ReShiki lässt sich nicht per AppleScript steuern; ein einzelnes Dokument kann ChemJournal dort nicht schließen.
/// Hat ChemJournal ReShiki selbst gestartet, beendet es ReShiki danach wieder (wie ChemDraw ohne weitere Dokumente;
/// ungesicherte andere Zeichnungen fragt ReShiki dabei selbst ab). Lief ReShiki schon vorher, bleibt es offen.
final class ReShikiBridge {
    /// Leere Zeichnung im Format von ReShiki 0.13 (`.rsk` ist JSON; neuere Versionen lesen ältere Dateien).
    static let emptyDocument = """
    {"atom_labels":{"carbons":"skeletal","hydrogens":true,"stereo":false},"version":29,\
    "atoms":[],"bonds":[],"annotations":[],"arrows":[],"graphics":[],"groups":[],"reactions":[]}
    """

    private(set) var fileURL: URL?
    var isActive: Bool { fileURL != nil }
    /// Zeitstempel der Datei, den der Wächter zuletzt gesehen hat.
    var lastSeenFileDate = Date.distantPast
    /// ReShiki lief schon einmal, seit wir die Datei geöffnet haben – läuft es danach nicht mehr, wurde es beendet.
    private(set) var sawAppRunning = false
    /// ReShiki lief beim Öffnen noch nicht – ChemJournal hat es gestartet und darf es am Ende wieder beenden.
    private var launchedByUs = false

    private static var runningApps: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: DrawingApp.reShiki.bundleIdentifier)
    }

    enum OpenResult { case opened, notInstalled, failed }

    /// Schreibt die Zeichnung in eine temporäre `.rsk`-Datei und öffnet sie in ReShiki.
    func open(drawing: Data? = nil) -> OpenResult {
        guard let app = DrawingApp.reShiki.applicationURL else { return .notInstalled }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ChemJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Reaktion_\(UUID().uuidString.prefix(8)).rsk")
        do { try (drawing ?? Data(Self.emptyDocument.utf8)).write(to: url) } catch { return .failed }
        fileURL = url
        sawAppRunning = false
        launchedByUs = Self.runningApps.isEmpty
        lastSeenFileDate = Self.modificationDate(of: url) ?? Date()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
        return .opened
    }

    /// Neuer Zeitstempel, wenn ReShiki die Datei seit dem letzten Blick gesichert hat.
    func changedFileDate() -> Date? {
        guard let url = fileURL, let date = Self.modificationDate(of: url), date > lastSeenFileDate else { return nil }
        lastSeenFileDate = date
        return date
    }

    /// `false`, sobald ReShiki nach dem Öffnen wieder beendet wurde.
    func appStillRunning() -> Bool {
        let running = !Self.runningApps.isEmpty
        if running { sawAppRunning = true }
        return running || !sawAppRunning
    }

    /// Modus beenden. Die Datei bleibt liegen: ReShiki hat sie womöglich noch offen.
    /// - Parameter quitApp: ReShiki beenden, wenn ChemJournal es gestartet hat (wie ChemDraw nach dem Import).
    func cleanup(quitApp: Bool) {
        fileURL = nil
        if quitApp, launchedByUs { Self.runningApps.forEach { $0.terminate() } }
        launchedByUs = false
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Bild (PNG auf Weiß) und Zeichnung einer `.rsk`-Datei; `nil`, wenn sie leer ist oder ReShiki sie nicht lesen kann.
    nonisolated static func render(_ rskURL: URL) async -> (png: Data, drawing: Data)? {
        guard let app = await MainActor.run(body: { DrawingApp.reShiki.applicationURL }),
              let drawing = try? Data(contentsOf: rskURL),
              DrawingStore.containsDrawing(drawing, app: .reShiki) else { return nil }
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("ReShiki_Export_\(UUID().uuidString.prefix(8)).png")
        defer { try? FileManager.default.removeItem(at: png) }
        let process = Process()
        process.executableURL = app.appendingPathComponent("Contents/MacOS/reshiki")
        // Vorschau-Größe: bis 2400 × 1600 Pixel, wie ein ChemDraw-Export (der Export mit 1200 dpi wäre viel zu groß)
        process.arguments = ["--cli", "render", rskURL.path, "-o", png.path, "--width", "2400", "--height", "1600", "--force"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: png), NSBitmapImageRep(data: data) != nil else { return nil }
        return (data, drawing)
    }
}
