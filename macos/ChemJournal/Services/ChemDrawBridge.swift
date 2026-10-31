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
    /// ChemDraw hatte unser Dokument schon offen – fehlt es danach, hat der Nutzer es geschlossen oder ChemDraw beendet.
    private var documentSeen = false
    /// Unser Dokument ist in ChemDraw nicht mehr offen.
    private(set) var documentClosed = false

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
            if not ((name of every document) contains "\(name)") then return "none"
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
                case "false": self.documentWasClean = true; self.documentStateDate = Date(); self.documentSeen = true
                case "true": self.documentWasClean = false; self.documentStateDate = Date(); self.documentSeen = true
                // Direkt nach dem Öffnen startet ChemDraw noch – erst „weg“, wenn es schon einmal da war
                case "none": if self.documentSeen { self.documentClosed = true }
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

    /// Leere Zeichnung im Querformat (A4 quer). Seitenrahmen und Druckeinstellung (`MacPrintInfo`) stammen aus einer
    /// Datei, die ChemDraw selbst im Querformat gespeichert hat; mit nacktem `<page>` öffnet ChemDraw Hochformat.
    static let landscapeTemplate = """
    <?xml version="1.0" encoding="UTF-8" ?>
    <!DOCTYPE CDXML SYSTEM "http://www.cambridgesoft.com/xml/cdxml.dtd">
    <CDXML PrintMargins="35.97 35.97 35.97 35.97" \
    MacPrintInfo="00030000025802580000000012981A9FFF9CFF9C12FC1B030365057B03E000020000025802580000000012981A9F000100000064000000010001010100020001270F000100010000000000000000000000000002001901900000000000600000000000000000000100000000000000000000000000000000">
      <page BoundingBox="0 0 769.86 523.26" HeaderPosition="36" FooterPosition="36" PrintTrimMarks="yes" HeightPages="1" WidthPages="1">
      </page>
    </CDXML>
    """

    /// Erstellt eine temporäre .cdxml-Datei und öffnet ChemDraw – leer oder mit einer gespeicherten Zeichnung.
    func openChemDraw(drawing: Data? = nil) {
        let fileURL = Self.tempDirectory.appendingPathComponent("Reaktion_\(UUID().uuidString.prefix(8)).cdxml")
        do {
            try (drawing ?? Data(Self.landscapeTemplate.utf8)).write(to: fileURL)
        } catch {
            print("ChemDraw Bridge: Konnte temporäre Datei nicht erstellen: \(error)")
            return
        }
        tempFileURL = fileURL
        documentSeen = false
        documentClosed = false
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
        arrangeWindowLandscape(documentName: fileURL.lastPathComponent)
    }

    /// Bringt das ChemDraw-Fenster unseres Dokuments ins Querformat, mittig auf dem Bildschirm von ChemJournal.
    /// ChemDraw braucht nach dem Öffnen etwas, bis das Dokument da ist – deshalb einige Sekunden lang nachfragen.
    private func arrangeWindowLandscape(documentName: String) {
        // Bildschirm des ChemJournal-Fensters (NSScreen.main wäre der Bildschirm der App, die gerade vorne ist)
        let ownWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
        guard let screen = ownWindow?.screen ?? NSScreen.main,
              let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let visible = screen.visibleFrame
        let width = min(visible.width - 80, 1400)
        let height = min(visible.height - 60, (width * 0.66).rounded())
        let x = (visible.midX - width / 2).rounded()
        let y = (visible.midY - height / 2).rounded()
        // AppleScript zählt von oben links des Hauptbildschirms, AppKit von unten links
        let left = Int(x), right = Int(x + width)
        let top = Int(primaryHeight - (y + height)), bottom = Int(primaryHeight - y)
        let name = documentName.replacingOccurrences(of: "\"", with: "")
        let script = """
        tell application "System Events"
            if not (exists (process "ChemDraw")) then return "wait"
        end tell
        tell application "ChemDraw"
            if not ((name of every document) contains "\(name)") then return "wait"
            set bounds of (window of document "\(name)") to {\(left), \(top), \(right), \(bottom)}
            return "ok"
        end tell
        """
        Task.detached(priority: .utility) {
            for _ in 0..<30 {
                if Self.runAppleScript(script, wait: true) != "wait" { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    enum ImportResult {
        /// Bild der Zeichnung und die Zeichnung selbst (CDXML), falls sie sich lesen ließ.
        case image(Data, drawing: Data?)
        /// Unser Dokument ist in ChemDraw nicht (mehr) offen – geschlossen oder ChemDraw beendet.
        case documentGone
        case failed
    }

    /// Exportiert die aktuelle Zeichnung aus ChemDraw (PNG, sonst PDF), schließt sie und gibt das Bild zurück.
    /// Der AppleScript-Aufruf blockiert und läuft deshalb im Hintergrund; `completion` kommt auf dem Main-Thread.
    func importFromChemDraw(completion: @escaping @MainActor (ImportResult) -> Void) {
        let baseName = "ChemDraw_Export_\(UUID().uuidString.prefix(8))"
        let pngURL = Self.tempDirectory.appendingPathComponent(baseName + ".png")
        let pdfURL = Self.tempDirectory.appendingPathComponent(baseName + ".pdf")
        // ChemDraw versteht kein „exists“ – deshalb Abgleich über die Dokumentnamen.
        // Gezielt das von ChemJournal geöffnete Dokument – nicht das vorderste. Liegt in ChemDraw ein anderes
        // Dokument vorne, würde sonst dessen Zeichnung übernommen und es ohne Sichern geschlossen.
        guard let docURL = tempFileURL else { completion(.documentGone); return }
        let docName = docURL.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        let script = """
        tell application "System Events"
            set isRunning to (exists (process "ChemDraw"))
        end tell
        if isRunning then
            tell application "ChemDraw"
                if (name of every document) contains "\(docName)" then
                    set d to document "\(docName)"
                    try
                        save d
                    end try
                    try
                        save d in POSIX file "\(pngURL.path)" as "PNG"
                    end try
                    try
                        save d in POSIX file "\(pdfURL.path)" as "PDF"
                    end try
                    try
                        close d saving no
                    end try
                    if (count of documents) = 0 then quit
                    return "ok"
                else
                    if (count of documents) = 0 then quit
                    return "no_doc"
                end if
            end tell
        else
            return "not_running"
        end if
        """

        Task.detached(priority: .userInitiated) {
            let answer = Self.runAppleScript(script, wait: true)
            try? await Task.sleep(for: .milliseconds(150))   // kurze Pause für das Dateisystem
            let data = Self.readExport(png: pngURL, pdf: pdfURL)
            // Das Skript hat die Zeichnung vorher in unsere Datei gesichert
            let drawing = (try? Data(contentsOf: docURL)).flatMap { DrawingStore.containsDrawing($0) ? $0 : nil }
            let result: ImportResult
            if let data { result = .image(data, drawing: drawing) }
            else if answer == "no_doc" || answer == "not_running" { result = .documentGone }
            else { result = .failed }
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
