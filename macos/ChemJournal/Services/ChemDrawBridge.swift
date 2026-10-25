import AppKit

/// Öffnet ChemDraw mit einer leeren Zeichnung und holt das Ergebnis als Bild zurück.
final class ChemDrawBridge {

    private(set) var tempFileURL: URL?
    var isActive: Bool { tempFileURL != nil }

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

    nonisolated private static func runAppleScript(_ source: String, wait: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            if wait { process.waitUntilExit() }
        } catch {
            print("ChemDraw Bridge: osascript Fehler: \(error)")
        }
    }
}
