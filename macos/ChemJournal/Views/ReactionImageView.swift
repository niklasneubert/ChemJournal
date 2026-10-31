import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Reaktionsgleichung: Bild/PDF per Drag & Drop, aus der Zwischenablage oder direkt aus ChemDraw bzw. ReShiki.
/// Welches Zeichenprogramm die Knöpfe zeigen, legen die Einstellungen fest; das andere gibt es über das kleine +.
struct ReactionImageView: View {
    @Binding var imageData: Data?
    @State private var isHovering = false          // Drag & Drop über der Fläche
    @State private var isPointerOverImage = false  // Maus über dem Bild → Entfernen-Knopf zeigen
    @State private var isChemDrawActive = false
    @State private var chemDrawBridge = ChemDrawBridge()
    @State private var showImportError = false
    /// Programm, aus dem der letzte Import fehlschlug (für die Meldung).
    @State private var importErrorApp = DrawingApp.chemDraw
    @State private var localMonitor: Any? = nil
    @State private var fileWatcherTimer: Timer?
    @State private var isImporting = false
    /// Kurze Bestätigung nach dem Kopieren.
    @State private var showCopied = false
    /// Gespeicherte Zeichnung zum aktuellen Bild (höchstens 7 Tage alt) – dann lässt es sich bearbeiten.
    @State private var savedDrawing: DrawingStore.SavedDrawing?
    @State private var reShikiBridge = ReShikiBridge()
    @State private var isReShikiActive = false
    @State private var reShikiWatcher: Timer?
    /// Programm, das nicht installiert ist (Hinweis anzeigen).
    @State private var missingApp: DrawingApp?
    @AppStorage(DrawingApp.defaultsKey) private var preferredAppRaw = DrawingApp.chemDraw.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var preferredApp: DrawingApp { DrawingApp(rawValue: preferredAppRaw) ?? .chemDraw }
    private var isDrawingActive: Bool { isChemDrawActive || isReShikiActive }
    private var canEditDrawing: Bool { savedDrawing != nil && !isDrawingActive && !isImporting }

    private var editHelp: String {
        guard let saved = savedDrawing else { return "" }
        return String(localized: "Zeichnung in \(saved.app.displayName) öffnen und bearbeiten (möglich bis \(saved.expires.formatted(date: .abbreviated, time: .shortened)))")
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Reaktionsgleichung").font(.headline)
                Spacer()
                if isChemDrawActive {
                    Button(action: { importFromChemDraw() }) {
                        Label("Zeichnung importieren (⌘D)", systemImage: "square.and.arrow.down")
                            .font(.subheadline).foregroundColor(.green)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.green.opacity(0.1)).cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button(action: { stopChemDraw() }) {
                        Label("Beenden", systemImage: "xmark.circle")
                            .font(.subheadline).foregroundColor(.gray)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1)).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
                if isReShikiActive {
                    // Gleiche Knöpfe wie bei ChemDraw
                    Button(action: { importFromReShiki() }) {
                        Label("Zeichnung importieren (⌘D)", systemImage: "square.and.arrow.down")
                            .font(.subheadline).foregroundColor(.green)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.green.opacity(0.1)).cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button(action: { stopReShiki(quitApp: true) }) {
                        Label("Beenden", systemImage: "xmark.circle")
                            .font(.subheadline).foregroundColor(.gray)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1)).cornerRadius(6)
                    }.buttonStyle(.plain)
                }
                if canEditDrawing, let saved = savedDrawing {
                    Button(action: { editDrawing() }) {
                        Label(String(localized: "In \(saved.app.displayName) bearbeiten"), systemImage: "pencil")
                            .font(.subheadline).foregroundColor(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1)).cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(editHelp)
                }
                Button(action: { startDrawing(in: preferredApp) }) {
                    Label(String(localized: "In \(preferredApp.displayName) zeichnen"), systemImage: "paintbrush.pointed")
                        .font(.subheadline).foregroundColor(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1)).cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isReShikiActive)
                // Das andere Zeichenprogramm
                Menu {
                    Button(String(localized: "In \(preferredApp.other.displayName) zeichnen")) { startDrawing(in: preferredApp.other) }
                        .disabled(isDrawingActive)
                    Divider()
                    SettingsLink { Text("Standardprogramm in den Einstellungen wählen …") }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Mit \(preferredApp.other.displayName) zeichnen"))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.blue.opacity(0.1) : Color(NSColor.textBackgroundColor).opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isHovering ? Color.blue : (isDrawingActive ? Color.orange : Color.gray.opacity(0.2)), style: StrokeStyle(lineWidth: isHovering || isDrawingActive ? 2 : 1, dash: isHovering ? [8] : [])))
                if let data = imageData, let image = NSImage(data: data) {
                    // ChemDraw-Bilder sind schwarz auf transparent – im Dunkelmodus auf heller Karte zeigen
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 250)
                        .padding(8)
                        .background(colorScheme == .dark ? Color.white.opacity(0.92) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                        // Klick auf die Zeichnung öffnet sie wieder im Zeichenprogramm (solange sie gespeichert ist)
                        .onTapGesture { if canEditDrawing { editDrawing() } }
                        .pointerStyle(canEditDrawing ? .link : nil)
                        .help(canEditDrawing ? editHelp : "")
                        .contextMenu {
                            Button(action: copyImage) { Label("Bild kopieren", systemImage: "doc.on.doc") }
                            Button(action: pasteImage) { Label("Bild aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") }
                            if canEditDrawing, let saved = savedDrawing {
                                Button(action: editDrawing) { Label(String(localized: "In \(saved.app.displayName) bearbeiten"), systemImage: "pencil") }
                            }
                            Divider()
                            Button(role: .destructive, action: removeImage) { Label("Bild entfernen", systemImage: "xmark") }
                        }
                    VStack {
                        HStack {
                            RemoveImageButton(action: removeImage)
                                .opacity(isPointerOverImage ? 1 : 0)
                                .allowsHitTesting(isPointerOverImage)
                                .animation(.easeOut(duration: 0.15), value: isPointerOverImage)
                                .padding(8)
                            Spacer()
                            if showCopied {
                                Label("Kopiert", systemImage: "checkmark").font(.caption).fontWeight(.medium)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.regularMaterial, in: Capsule())
                                    .transition(.opacity)
                            }
                            // Immer sichtbar und kräftig gefärbt – auch im Dunkelmodus auf der hellen Bildkarte gut zu sehen
                            Button(action: copyImage) {
                                Label("Kopieren", systemImage: "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Color.accentColor, in: Capsule())
                                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Bild in die Zwischenablage kopieren – in einem anderen Ansatz mit „Aus Zwischenablage einfügen“ einsetzen")
                            .padding(10)
                        }
                        Spacer()
                        if isReShikiActive {
                            HStack(spacing: 6) {
                                Image(systemName: "paintbrush.pointed.fill").foregroundColor(.orange)
                                Text("ReShiki aktiv").font(.caption).fontWeight(.medium).foregroundColor(.orange)
                                Text("–").foregroundColor(.orange.opacity(0.5))
                                Text("In ReShiki ⌘S drücken oder hier ⌘D zum Importieren").font(.caption).foregroundColor(.orange)
                            }
                            .padding(6).background(Color.orange.opacity(0.15)).cornerRadius(6).padding(8)
                        }
                        if isChemDrawActive {
                            HStack(spacing: 6) {
                                Image(systemName: "paintbrush.pointed.fill").foregroundColor(.orange)
                                Text("ChemDraw aktiv").font(.caption).fontWeight(.medium).foregroundColor(.orange)
                                Text("–").foregroundColor(.orange.opacity(0.5))
                                Text("In ChemDraw ⌘S drücken oder hier ⌘D zum Importieren").font(.caption).foregroundColor(.orange)
                            }
                            .padding(6).background(Color.orange.opacity(0.15)).cornerRadius(6).padding(8)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        if isReShikiActive {
                            Image(systemName: "paintbrush.pointed.fill").font(.largeTitle).foregroundColor(.orange)
                            Text("In ReShiki zeichnen & ⌘S drücken").font(.headline).foregroundColor(.orange)
                            Text("ReShiki speichert und ChemJournal importiert das Bild automatisch").font(.body).foregroundColor(.orange)
                            Text("Alternativ hier ⌘D oder den Button oben nutzen").font(.caption).foregroundColor(.secondary)
                        } else if isChemDrawActive {
                            Image(systemName: "paintbrush.pointed.fill").font(.largeTitle).foregroundColor(.orange)
                            Text("In ChemDraw zeichnen & ⌘S drücken").font(.headline).foregroundColor(.orange)
                            Text("ChemDraw speichert, schließt sich automatisch und importiert das Bild").font(.body).foregroundColor(.orange)
                            Text("Alternativ hier ⌘D oder den Button oben nutzen").font(.caption).foregroundColor(.secondary)
                        } else {
                            Image(systemName: "photo.badge.arrow.down").font(.largeTitle).foregroundColor(.blue)
                            Text("Bild oder PDF (ChemDraw) hier ablegen").font(.body).foregroundColor(.blue)
                            Button(action: pasteImage) { Label("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") }
                                .buttonStyle(.borderless)
                                .help("Ein kopiertes Reaktionsbild (z. B. aus einem anderen Ansatz) oder eine Zeichnung aus ChemDraw einfügen")
                        }
                    }.padding(40)
                    .contextMenu {
                        Button(action: pasteImage) { Label("Bild aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") }
                    }
                }
            }.frame(minHeight: 120)
            .onHover { inside in isPointerOverImage = inside }
            .onDrop(of: [UTType.image.identifier, UTType.pdf.identifier, UTType.fileURL.identifier], isTargeted: $isHovering) { providers in
                handleDrop(providers)
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromChemDraw)) { _ in
                if isChemDrawActive { importFromChemDraw() }
                if isReShikiActive { importFromReShiki() }
            }
            .onDisappear {
                // Nur aufräumen, wenn diese Ansicht das Zeichenprogramm auch geöffnet hat
                if isChemDrawActive { stopChemDraw() }
                if isReShikiActive { stopReShiki(quitApp: true) }
            }
            .task(id: imageData) { refreshSavedDrawing() }
            .alert("Import fehlgeschlagen", isPresented: $showImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                if importErrorApp == .reShiki {
                    Text("Konnte kein Bild aus ReShiki importieren.\nBitte stelle sicher, dass eine Zeichnung in ReShiki vorhanden ist und mit ⌘S gesichert wurde.")
                } else {
                    Text("Konnte kein Bild aus ChemDraw importieren.\nBitte stelle sicher, dass eine Zeichnung in ChemDraw vorhanden ist.")
                }
            }
            .alert(String(localized: "\(missingApp?.displayName ?? "") ist nicht installiert"),
                   isPresented: Binding(get: { missingApp != nil }, set: { if !$0 { missingApp = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(missingApp == .reShiki
                     ? String(localized: "ReShiki ist kostenlos und quelloffen (reshiki.com). Nach der Installation hier einfach erneut klicken.")
                     : String(localized: "Installiere ChemDraw oder wähle in den Einstellungen ReShiki als Zeichenprogramm."))
            }
        }
    }

    private func copyImage() {
        guard let data = imageData else { return }
        ReactionImagePasteboard.write(data)
        withAnimation(.easeOut(duration: 0.15)) { showCopied = true }
        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation(.easeOut(duration: 0.3)) { showCopied = false } }
    }

    private func pasteImage() {
        if let data = ReactionImagePasteboard.read() {
            imageData = data
        } else {
            NSSound.beep()   // nichts Passendes in der Zwischenablage
        }
    }

    private func removeImage() {
        withAnimation(.easeOut(duration: 0.15)) { imageData = nil }
    }

    // MARK: - Drag & Drop (Callbacks kommen im Hintergrund)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let binding = $imageData
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in binding.wrappedValue = data }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, _ in
                guard let data, let png = PDFRendering.firstPagePNG(from: data, scale: 2, whiteBackground: false) else { return }
                Task { @MainActor in binding.wrappedValue = png }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let fileURL = url, let data = try? Data(contentsOf: fileURL) else { return }
                let result: Data?
                if fileURL.pathExtension.lowercased() == "pdf" {
                    result = PDFRendering.firstPagePNG(from: data, scale: 2, whiteBackground: false)
                } else {
                    result = NSBitmapImageRep(data: data) != nil || NSImage(data: data) != nil ? data : nil
                }
                guard let result else { return }
                Task { @MainActor in binding.wrappedValue = result }
            }
            return true
        }
        return false
    }

    // MARK: - Zeichenprogramm

    /// Sucht die gespeicherte Zeichnung zum aktuellen Bild und räumt abgelaufene weg.
    private func refreshSavedDrawing() {
        DrawingStore.purgeExpired()
        savedDrawing = imageData.flatMap { DrawingStore.drawing(for: $0) }
    }

    private func startDrawing(in app: DrawingApp, drawing: Data? = nil) {
        switch app {
        case .chemDraw:
            guard DrawingApp.chemDraw.isInstalled else { missingApp = .chemDraw; return }
            openChemDraw(drawing: drawing)
        case .reShiki:
            startReShiki(drawing: drawing)
        }
    }

    /// Öffnet die gespeicherte Zeichnung in dem Programm, mit dem sie entstand. Import ersetzt dann das Bild.
    private func editDrawing() {
        guard let saved = savedDrawing, let drawing = try? Data(contentsOf: saved.url) else {
            refreshSavedDrawing()
            return
        }
        startDrawing(in: saved.app, drawing: drawing)
    }

    // MARK: - ReShiki

    private func startReShiki(drawing: Data? = nil) {
        switch reShikiBridge.open(drawing: drawing) {
        case .notInstalled: missingApp = .reShiki
        case .failed: NSSound.beep()
        case .opened:
            isReShikiActive = true
            startKeyboardMonitors()
            startReShikiWatcher()
        }
    }

    /// Wie der ChemDraw-Import: gesicherten Stand rendern, als Bild übernehmen, Zeichnung 7 Tage aufheben, Modus beenden.
    private func importFromReShiki() {
        guard !isImporting, let url = reShikiBridge.fileURL else { return }
        isImporting = true
        Task {
            let result = await ReShikiBridge.render(url)
            isImporting = false
            NSApp.activate(ignoringOtherApps: true)
            guard let result else {
                // Leere oder noch nicht gesicherte Zeichnung: Meldung wie bei ChemDraw, Modus bleibt aktiv
                importErrorApp = .reShiki
                showImportError = true
                return
            }
            DrawingStore.save(result.drawing, for: result.png, app: .reShiki)
            imageData = result.png
            stopReShiki(quitApp: true)
        }
    }

    private func startReShikiWatcher() {
        reShikiWatcher?.invalidate()
        let bridge = reShikiBridge
        reShikiWatcher = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            Task { @MainActor in
                guard isReShikiActive else { return }
                // ReShiki beendet: Modus ebenfalls beenden
                guard bridge.appStillRunning() else { stopReShiki(quitApp: false); return }
                // ⌘S in ReShiki (ReShiki sichert Entwürfe getrennt – die Datei ändert sich nur beim Sichern)
                if bridge.changedFileDate() != nil { importFromReShiki() }
            }
        }
    }

    private func stopReShiki(quitApp: Bool) {
        reShikiWatcher?.invalidate()
        reShikiWatcher = nil
        stopKeyboardMonitors()
        reShikiBridge.cleanup(quitApp: quitApp)
        isReShikiActive = false
        refreshSavedDrawing()
    }

    // MARK: - ChemDraw

    private func openChemDraw(drawing: Data? = nil) {
        chemDrawBridge.openChemDraw(drawing: drawing)
        isChemDrawActive = chemDrawBridge.isActive
        guard isChemDrawActive else { return }
        startKeyboardMonitors()
        startFileWatcher()
    }

    private func importFromChemDraw() {
        // ⌘S, ⌘D und der Datei-Watcher können gleichzeitig auslösen – nur einen Import zulassen
        guard !isImporting else { return }
        isImporting = true
        stopFileWatcher()
        chemDrawBridge.importFromChemDraw { result in
            isImporting = false
            switch result {
            case .image(let data, let drawing):
                if let drawing { DrawingStore.save(drawing, for: data) }
                imageData = data
                stopChemDraw()
                refreshSavedDrawing()
            case .documentGone:
                // Zeichnung in ChemDraw geschlossen oder ChemDraw beendet: nichts zu importieren, kein Fehler
                stopChemDraw()
            case .failed:
                importErrorApp = .chemDraw
                showImportError = true
                chemDrawBridge.markFileSeen()
                if isChemDrawActive { startFileWatcher() }
            }
        }
    }

    private func stopChemDraw() {
        stopFileWatcher()
        stopKeyboardMonitors()
        chemDrawBridge.cleanup()
        isChemDrawActive = false
    }

    private func startFileWatcher() {
        stopFileWatcher()
        let bridge = chemDrawBridge
        fileWatcherTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                guard isChemDrawActive, let url = bridge.tempFileURL else { return }
                bridge.refreshDocumentState()
                // Zeichnung in ChemDraw ohne Import geschlossen: ChemDraw-Modus beenden, sonst bliebe er hängen
                if bridge.documentClosed { stopChemDraw(); return }
                guard let modDate = ChemDrawBridge.modificationDate(of: url), modDate > bridge.lastSeenFileDate else { return }
                bridge.lastSeenFileDate = modDate
                // ChemDraw sichert auch von selbst – nur bei ⌘S (Speichern) übernehmen
                if bridge.isExplicitSave(fileDate: modDate) { importFromChemDraw() }
            }
        }
    }

    private func stopFileWatcher() {
        fileWatcherTimer?.invalidate()
        fileWatcherTimer = nil
    }

    private func startKeyboardMonitors() {
        stopKeyboardMonitors()
        // Fängt ⌘D und ⌘Return in ChemJournal ab, solange ChemDraw aktiv ist. ⌘S nicht: das speichert in
        // ChemJournal das Laborjournal (früher löste es hier einen Import aus – mit Fehlermeldung, wenn ChemDraw
        // schon geschlossen war, und ohne zu speichern).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isChemDrawActive || isReShikiActive else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let code = event.keyCode
            // D = 2, Return = 36, Enter = 76
            if flags.contains(.command) && [2, 36, 76].contains(code) {
                if isChemDrawActive { importFromChemDraw() } else { importFromReShiki() }
                return nil
            }
            return event
        }
    }

    private func stopKeyboardMonitors() {
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
    }
}

/// Entfernen-Knopf im macOS-Stil (wie bei Mitteilungen und Widgets): kleiner Kreis aus Material mit
/// grauem "x", oben links, erscheint beim Darüberfahren. Wird beim Drüberfahren mit dem Knopf etwas dunkler.
private struct RemoveImageButton: View {
    let action: () -> Void
    @State private var pressedHover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(pressedHover ? .primary : .secondary)
                .frame(width: 20, height: 20)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { pressedHover = $0 }
        .help("Bild entfernen")
        .accessibilityLabel("Bild entfernen")
    }
}

/// Reaktionsbild in die Zwischenablage und zurück.
///
/// Beim Kopieren gehen die Originaldaten unter einem eigenen Typ mit; beim Einfügen in einen anderen Ansatz sind es
/// also genau dieselben Bytes. Damit findet ChemJournal auch dort die gespeicherte ChemDraw-Zeichnung (sie ist nach
/// dem Bild benannt) und das Bild bleibt in ChemDraw bearbeitbar. Andere Programme bekommen PNG und TIFF.
enum ReactionImagePasteboard {
    static let type = NSPasteboard.PasteboardType("de.chemjournal.reaction-image")

    static func write(_ data: Data, to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setData(data, forType: type)
        let png = isPNG(data) ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        if let png { item.setData(png, forType: .png) }
        if let tiff = NSImage(data: data)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Bild aus der Zwischenablage: eigenes Reaktionsbild, PNG, PDF (so kopiert ChemDraw), TIFF oder eine Bilddatei.
    static func read(from pasteboard: NSPasteboard = .general) -> Data? {
        if let data = pasteboard.data(forType: type), NSImage(data: data) != nil { return data }
        if let data = pasteboard.data(forType: .png), NSBitmapImageRep(data: data) != nil { return data }
        if let data = pasteboard.data(forType: .pdf),
           let png = PDFRendering.firstPagePNG(from: data, scale: 3, whiteBackground: false) { return png }
        if let data = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: data) {
            return rep.representation(using: .png, properties: [:])
        }
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first,
           let data = try? Data(contentsOf: url) {
            if url.pathExtension.lowercased() == "pdf" { return PDFRendering.firstPagePNG(from: data, scale: 2, whiteBackground: false) }
            if NSBitmapImageRep(data: data) != nil { return data }
        }
        return nil
    }

    private static func isPNG(_ data: Data) -> Bool { data.starts(with: [0x89, 0x50, 0x4E, 0x47]) }
}
