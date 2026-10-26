import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Reaktionsgleichung: Bild/PDF per Drag & Drop oder direkt aus ChemDraw.
struct ReactionImageView: View {
    @Binding var imageData: Data?
    @State private var isHovering = false          // Drag & Drop über der Fläche
    @State private var isPointerOverImage = false  // Maus über dem Bild → Entfernen-Knopf zeigen
    @State private var isChemDrawActive = false
    @State private var chemDrawBridge = ChemDrawBridge()
    @State private var showImportError = false
    @State private var localMonitor: Any? = nil
    @State private var fileWatcherTimer: Timer?
    @State private var isImporting = false

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
                Button(action: { openChemDraw() }) {
                    Label("In ChemDraw zeichnen", systemImage: "paintbrush.pointed")
                        .font(.subheadline).foregroundColor(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1)).cornerRadius(6)
                }.buttonStyle(.plain)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.blue.opacity(0.1) : Color(NSColor.textBackgroundColor).opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isHovering ? Color.blue : (isChemDrawActive ? Color.orange : Color.gray.opacity(0.2)), style: StrokeStyle(lineWidth: isHovering || isChemDrawActive ? 2 : 1, dash: isHovering ? [8] : [])))
                if let data = imageData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 250).padding()
                        .contextMenu {
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
                        }
                        Spacer()
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
                        if isChemDrawActive {
                            Image(systemName: "paintbrush.pointed.fill").font(.largeTitle).foregroundColor(.orange)
                            Text("In ChemDraw zeichnen & ⌘S drücken").font(.headline).foregroundColor(.orange)
                            Text("ChemDraw speichert, schließt sich automatisch und importiert das Bild").font(.body).foregroundColor(.orange)
                            Text("Alternativ hier ⌘D oder den Button oben nutzen").font(.caption).foregroundColor(.secondary)
                        } else {
                            Image(systemName: "photo.badge.arrow.down").font(.largeTitle).foregroundColor(.blue)
                            Text("Bild oder PDF (ChemDraw) hier ablegen").font(.body).foregroundColor(.blue)
                        }
                    }.padding(40)
                }
            }.frame(minHeight: 120)
            .onHover { inside in isPointerOverImage = inside }
            .onDrop(of: [UTType.image.identifier, UTType.pdf.identifier, UTType.fileURL.identifier], isTargeted: $isHovering) { providers in
                handleDrop(providers)
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromChemDraw)) { _ in
                if isChemDrawActive { importFromChemDraw() }
            }
            .onDisappear {
                // Nur aufräumen, wenn diese Ansicht ChemDraw auch geöffnet hat
                if isChemDrawActive { stopChemDraw() }
            }
            .alert("Import fehlgeschlagen", isPresented: $showImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Konnte kein Bild aus ChemDraw importieren.\nBitte stelle sicher, dass eine Zeichnung in ChemDraw vorhanden ist.")
            }
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

    // MARK: - ChemDraw

    private func openChemDraw() {
        chemDrawBridge.openChemDraw()
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
        chemDrawBridge.importFromChemDraw { data in
            isImporting = false
            if let data {
                imageData = data
                stopChemDraw()
            } else {
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
        // Fängt ⌘D, ⌘Return und ⌘S in ChemJournal ab, solange ChemDraw aktiv ist
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isChemDrawActive else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let code = event.keyCode
            // D = 2, Return = 36, Enter = 76, S = 1
            if flags.contains(.command) && [2, 36, 76, 1].contains(code) {
                importFromChemDraw()
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
