import AppKit

/// Öffnet ChemDraw mit einer leeren Zeichnung und holt das Ergebnis als Bild zurück.
final class ChemDrawBridge {

    private(set) var tempFileURL: URL?
    var isActive: Bool { tempFileURL != nil }

    // ChemDraw speichert CDXML-Dateien beim Bearbeiten von selbst (macOS-Autosichern, ca. 10–15 s nach einer
    // Änderung). Eine geänderte Datei heißt also nicht, dass ⌘S gedrückt wurde. So unterscheiden wir:
    // - ⌘S nach Änderungen legt eine neue Dateiversion mit dem Zeitstempel der Datei an. Das Autosichern nicht
    //   (beim ersten Mal sichert es nur den Stand beim Öffnen, mit dessen altem Zeitstempel).
    // - ⌘S ohne neue Änderungen schreibt die Datei, obwohl das Dokument gespeichert war. Das Autosichern
    //   schreibt nur Dokumente mit ungespeicherten Änderungen.
    private var documentWasClean: Bool?     // letzter bekannter Zustand in ChemDraw (nil = unbekannt)
    private var documentStateDate = Date.distantPast
    private var stateQueryRunning = false
    private var lastStateQuery = Date.distantPast
    /// Zeitstempel der Datei, den der Dateiwächter zuletzt gesehen hat.
    var lastSeenFileDate = Date.distantPast

    /// Fragt (höchstens einmal pro Sekunde, im Hintergrund) ab, ob unser Dokument in ChemDraw ungespeicherte
    /// Änderungen hat.
    func refreshDocumentState() {
        guard let url = tempFileURL, !stateQueryRunning, Date().timeIntervalSince(lastStateQuery) >= 1 else { return }
        stateQueryRunning = true
        lastStateQuery = Date()
        let name = url.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        let script = """
        tell application "System Events"
            if not (exists (process "ChemDraw")) then return "none"
        end tell
        tell application "ChemDraw"
            if not (exists document "\(name)") then return "none"
            return modified of document "\(name)" as text
        end tell
        """
        Task.detached(priority: .utility) {
            let answer = Self.runAppleScript(script, wait: true)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.stateQueryRunning = false
                guard self.tempFileURL == url else { return }
                switch answer {
                case "false": self.documentWasClean = true; self.documentStateDate = Date()
                case "true": self.documentWasClean = false; self.documentStateDate = Date()
                default: break
                }
            }
        }
    }

    /// Merkt sich den aktuellen Zeitstempel der Datei, damit der Dateiwächter ihn nicht als neues ⌘S zählt
    /// (der Import speichert das Dokument selbst).
    func markFileSeen() {
        guard let url = tempFileURL, let date = Self.modificationDate(of: url) else { return }
        lastSeenFileDate = max(lastSeenFileDate, date)
    }

    /// Ungecachter Zeitstempel (URL.resourceValues merkt sich Werte pro URL-Objekt).
    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// `true`, wenn die Änderung der Datei vom Speichern mit ⌘S stammt und nicht vom Autosichern.
    func isExplicitSave(fileDate: Date) -> Bool {
        guard let url = tempFileURL else { return false }
        let versions = NSFileVersion.otherVersionsOfItem(at: url) ?? []
        if versions.contains(where: { abs(($0.modificationDate ?? .distantPast).timeIntervalSince(fileDate)) < 2 }) { return true }
        // Nur einem frischen Zustand trauen (hängt ChemDraw, kommen keine Antworten mehr)
        if documentWasClean == true, fileDate.timeIntervalSince(documentStateDate) < 3 { return true }
        // Autosichern: danach ist das Dokument gespeichert, bis wieder etwas geändert wird
        documentWasClean = nil
        return false
    }

    private static var tempDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ChemJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Erstellt eine temporäre .cdxml-Datei und öffnet ChemDraw.
    func openChemDraw() {
        let fileURL = Self.tempDirectory.appendingPathComponent("Reaktion_\(UUID().uuidString.prefix(8)).cdxml")
        let template = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <!DOCTYPE CDXML SYSTEM "http://www.cambridgesoft.com/xml/cdxml.dtd">
        <CDXML>
          <page>
          </page>
        </CDXML>
        """
        do {
            try template.data(using: .utf8)?.write(to: fileURL)
        } catch {
            print("ChemDraw Bridge: Konnte temporäre Datei nicht erstellen: \(error)")
            return
        }
        tempFileURL = fileURL
        documentWasClean = nil
        documentStateDate = .distantPast
        lastSeenFileDate = Self.modificationDate(of: fileURL) ?? Date()

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let chemDrawURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.revvity.ChemDraw") {
            NSWorkspace.shared.open([fileURL], withApplicationAt: chemDrawURL, configuration: config)
        } else {
            NSWorkspace.shared.open(fileURL, configuration: config)
        }
    }

    /// Exportiert die aktuelle Zeichnung aus ChemDraw (PNG, sonst PDF), schließt sie und gibt das Bild zurück.
    /// Der AppleScript-Aufruf blockiert und läuft deshalb im Hintergrund; `completion` kommt auf dem Main-Thread.
    func importFromChemDraw(completion: @escaping @MainActor (Data?) -> Void) {
        let baseName = "ChemDraw_Export_\(UUID().uuidString.prefix(8))"
        let pngURL = Self.tempDirectory.appendingPathComponent(baseName + ".png")
        let pdfURL = Self.tempDirectory.appendingPathComponent(baseName + ".pdf")
        let script = """
        tell application "System Events"
            set isRunning to (exists (process "ChemDraw"))
        end tell
        if isRunning then
            tell application "ChemDraw"
                if (count of documents) > 0 then
                    try
                        save front document
                    end try
                    try
                        save front document in POSIX file "\(pngURL.path)" as "PNG"
                    end try
                    try
                        save front document in POSIX file "\(pdfURL.path)" as "PDF"
                    end try
                    try
                        close front document saving no
                    end try
                    if (count of documents) = 0 then quit
                    return "ok"
                else
                    quit
                    return "no_doc"
                end if
            end tell
        else
            return "not_running"
        end if
        """

        Task.detached(priority: .userInitiated) {
            Self.runAppleScript(script, wait: true)
            try? await Task.sleep(for: .milliseconds(150))   // kurze Pause für das Dateisystem
            let result = Self.readExport(png: pngURL, pdf: pdfURL)
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
                completion(result)
            }
        }
    }

    nonisolated private static func readExport(png pngURL: URL, pdf pdfURL: URL) -> Data? {
        defer {
            try? FileManager.default.removeItem(at: pngURL)
            try? FileManager.default.removeItem(at: pdfURL)
        }
        let pngData = try? Data(contentsOf: pngURL)
        // 1. PNG (ChemDraw schneidet es auf die Moleküle zu), sofern nicht leer
        if let pngData, let rep = NSBitmapImageRep(data: pngData), rep.pixelsWide > 20 || rep.pixelsHigh > 20 { return pngData }
        // 2. PDF rendern
        if let pdfData = try? Data(contentsOf: pdfURL),
           let rendered = PDFRendering.firstPagePNG(from: pdfData, scale: 3, whiteBackground: true) { return rendered }
        // 3. Jedes lesbare PNG
        if let pngData, NSBitmapImageRep(data: pngData) != nil { return pngData }
        return nil
    }

    /// Räumt die temporäre Datei auf und schließt nur das von ChemJournal geöffnete Dokument.
    ///
    /// Vorher wurde hier `close front document saving no` ausgeführt – auch beim bloßen Wechseln des Ansatzes.
    /// War in ChemDraw gerade ein anderes Dokument vorne, ging dessen ungespeicherter Inhalt verloren.
    func cleanup() {
        guard let url = tempFileURL else { return }
        tempFileURL = nil
        let docName = url.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        try? FileManager.default.removeItem(at: url)

        let quitScript = """
        tell application "System Events"
            if not (exists (process "ChemDraw")) then return
        end tell
        tell application "ChemDraw"
            try
                close (every document whose name is "\(docName)") saving no
            end try
            if (count of documents) = 0 then quit
        end tell
        """
        Task.detached { Self.runAppleScript(quitScript, wait: false) }
    }

    /// Führt ein AppleScript aus; mit `wait` kommt die Ausgabe zurück.
    @discardableResult
    nonisolated private static func runAppleScript(_ source: String, wait: Bool) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            guard wait else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("ChemDraw Bridge: osascript Fehler: \(error)")
            return nil
        }
    }
}
