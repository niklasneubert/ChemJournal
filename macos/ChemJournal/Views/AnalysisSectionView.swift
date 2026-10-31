import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// „Aufreinigung & Analytik“ einer Stufe: beliebig viele Einträge (NMR, IR, MS, Säule, Umkristallisation …), jeder mit
/// eigenem Formular und verknüpften Dateien.
struct AnalysisSectionView: View {
    @Binding var entries: [AnalysisEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Aufreinigung & Analytik").font(.headline)
                Spacer()
                if !entries.isEmpty { addMenu }
            }
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Messung oder Aufreinigungsschritt hinzufügen:").font(.callout).foregroundStyle(.secondary)
                    ForEach(AnalysisGroup.allCases, id: \.self) { group in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.title).font(.caption).foregroundStyle(.secondary).frame(width: 190, alignment: .leading)
                            FlowLayout(spacing: 6) {
                                ForEach(group.methods, id: \.self) { method in
                                    Button { add(method) } label: { MethodBadge(method: method) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            ForEach($entries) { $entry in
                AnalysisEntryCard(entry: $entry,
                                  onDuplicate: { duplicate(entry.id) },
                                  onMove: { move(entry.id, by: $0) },
                                  onDelete: { withAnimation(.easeOut(duration: 0.15)) { entries.removeAll { $0.id == entry.id } } },
                                  canMoveUp: entries.first?.id != entry.id,
                                  canMoveDown: entries.last?.id != entry.id)
            }
        }
        .padding(12).background(Color(NSColor.textBackgroundColor).opacity(0.5)).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }

    private var addMenu: some View {
        Menu {
            ForEach(AnalysisGroup.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(group.methods, id: \.self) { method in
                        Button { add(method) } label: { Label(method.title, systemImage: method.symbol) }
                    }
                }
            }
        } label: {
            Label("Hinzufügen", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Weitere Messung oder Aufreinigung zu dieser Stufe hinzufügen")
    }

    /// Neuer Eintrag; übernimmt Lösungsmittel, Eluent usw. vom letzten Eintrag derselben Methode.
    private func add(_ method: AnalysisMethod) {
        var entry = AnalysisEntry(method: method)
        if let last = entries.last(where: { $0.method == method }) {
            for key in method.inheritedKeys { if let v = last.values[key], !v.isEmpty { entry.values[key] = v } }
            entry.sample = last.sample
        }
        withAnimation(.easeOut(duration: 0.15)) { entries.append(entry) }
    }

    private func duplicate(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var copy = entries[i]
        copy.id = UUID(); copy.createdAt = Date(); copy.files = copy.files.map { var f = $0; f.id = UUID(); return f }
        entries.insert(copy, at: i + 1)
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries.indices.contains(i + offset) else { return }
        entries.swapAt(i, i + offset)
    }
}

/// Farbiges Symbol mit Methodenname (für die Schnellauswahl).
private struct MethodBadge: View {
    let method: AnalysisMethod
    var body: some View {
        Label(method.title, systemImage: method.symbol)
            .font(.caption).fontWeight(.medium)
            .foregroundStyle(method.tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(method.tint.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
    }
}

extension AnalysisMethod {
    var tint: Color {
        switch group {
        case .spectroscopy: .blue
        case .purification: .green
        case .other: .gray
        }
    }
}

/// Karte eines Eintrags: Kopf (Methode, Probe, Aktionen), Formular der Methode, berechnete Werte, Dateien.
struct AnalysisEntryCard: View {
    @Binding var entry: AnalysisEntry
    var onDuplicate: () -> Void
    var onMove: (Int) -> Void
    var onDelete: () -> Void
    var canMoveUp: Bool
    var canMoveDown: Bool
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if entry.isExpanded {
                form
                if !entry.results.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(entry.results, id: \.self) { r in
                            Label("\(r.label): \(r.value)", systemImage: "function")
                                .font(.caption).foregroundStyle(entry.method.tint)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(entry.method.tint.opacity(0.1), in: Capsule())
                        }
                    }
                }
                files
            } else {
                Text(verbatim: entry.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            // Farbstreifen: blau = Spektroskopie, grün = Aufreinigung
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8).fill(entry.method.tint.opacity(0.7)).frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isDropTarget ? Color.accentColor : Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: isDropTarget ? [6] : [])))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in linkDroppedFiles(providers) }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.15)) { entry.isExpanded.toggle() } } label: {
                Image(systemName: "chevron.right").rotationEffect(.degrees(entry.isExpanded ? 90 : 0))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 14)
            }
            .buttonStyle(.plain)
            .help(entry.isExpanded ? "Einklappen" : "Aufklappen")
            Image(systemName: entry.method.symbol).foregroundStyle(entry.method.tint)
            Text(verbatim: entry.heading).font(.subheadline.weight(.semibold))
            TextField("Probe", text: $entry.sample)
                .textFieldStyle(.plain).font(.subheadline).foregroundStyle(.secondary)
                .frame(minWidth: 120, maxWidth: 260)
            Spacer()
            if !entry.isExpanded, !entry.files.isEmpty {
                Label("\(entry.files.count)", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary)
                    .help("Verknüpfte Dateien")
            }
            Menu {
                Button("Duplizieren", action: onDuplicate)
                Button("Nach oben") { onMove(-1) }.disabled(!canMoveUp)
                Button("Nach unten") { onMove(1) }.disabled(!canMoveDown)
                Divider()
                Button("Zusammenfassung kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.summary, forType: .string)
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Weitere Aktionen")
            Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(.red) }
                .buttonStyle(.plain)
                .help("Eintrag entfernen (⌘Z macht es rückgängig)")
        }
    }

    // MARK: Formular

    private var form: some View {
        let fields = entry.method.fields
        return VStack(alignment: .leading, spacing: 10) {
            let short = fields.filter { !$0.isMultiline }
            if !short.isEmpty {
                // Feste Zellbreite, umbrechend: gleichmäßige Spalten ohne Lazy-Grid (das baut Zellen erst beim Sichtbarwerden)
                FlowLayout(spacing: 12) {
                    ForEach(short) { field in fieldCell(field).frame(width: 230, alignment: .leading) }
                }
            }
            ForEach(fields.filter(\.isMultiline)) { field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: field.label).font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: value(field.key))
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                    .font(.body)
                    .frame(minHeight: 44)
                    .padding(5)
                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.25), lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func fieldCell(_ field: AnalysisField) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: field.label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                // Leerer Platzhalter: ohne ihn zeigt macOS die Feldbezeichnung grau im Feld
                TextField(text: value(field.key), prompt: Text(verbatim: "")) { Text(verbatim: field.label) }
                    .textFieldStyle(.roundedBorder)
                // Vorschläge oder Einheit in gleich breitem Platz, damit die Eingabefelder bündig sind
                fieldAccessory(field).frame(width: (field.unit?.count ?? 0) > 4 ? 72 : 44, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func fieldAccessory(_ field: AnalysisField) -> some View {
        if case .multiChoice(let options) = field.kind {
            MultiChoiceButton(options: options, text: value(field.key))
        } else if case .choice(let options) = field.kind {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button { value(field.key).wrappedValue = option } label: {
                        if value(field.key).wrappedValue == option { Label(option, systemImage: "checkmark") } else { Text(verbatim: option) }
                    }
                }
            } label: { Image(systemName: "chevron.down") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Vorschläge – eigene Eingabe ist auch möglich")
        } else if let unit = field.unit {
            Text(verbatim: unit).font(.callout).foregroundStyle(.secondary).fixedSize()
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private func value(_ key: String) -> Binding<String> {
        Binding(get: { entry.values[key] ?? "" },
                set: { entry.values[key] = $0.isEmpty ? nil : $0 })
    }

    // MARK: Dateien

    private var files: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entry.files) { $file in
                AnalysisFileRow(file: $file) { entry.files.removeAll { $0.id == file.id } }
            }
            Button(action: chooseFiles) {
                Label(entry.method == .nmr ? "NMR-Daten verknüpfen" : "Datei verknüpfen", systemImage: "paperclip")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .help("Spektrum, Rohdaten oder Ordner verknüpfen – oder Dateien auf die Karte ziehen")
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        // NMR-Rohdaten (Bruker, Varian) sind Ordner
        panel.canChooseDirectories = true
        panel.message = String(localized: "Dateien oder Ordner zu „\(entry.heading)“ verknüpfen")
        if panel.runModal() == .OK { link(panel.urls) }
    }

    private func link(_ urls: [URL]) {
        for url in urls where !entry.files.contains(where: { $0.filePath == url.path }) {
            entry.files.append(AnalysisFile(filePath: url.path))
        }
    }

    private func linkDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let binding = $entry
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if !binding.wrappedValue.files.contains(where: { $0.filePath == url.path }) {
                        binding.wrappedValue.files.append(AnalysisFile(filePath: url.path))
                    }
                }
            }
        }
        return accepted
    }
}

/// Mehrfachauswahl (z. B. NMR-Kerne): Häkchen in einem kleinen Fenster, das Feld bleibt frei editierbar.
private struct MultiChoiceButton: View {
    let options: [String]
    @Binding var text: String
    @State private var show = false

    private var selected: [String] { AnalysisEntry.list(text) }

    var body: some View {
        Button { show = true } label: { Image(systemName: "chevron.down") }
            .buttonStyle(.borderless)
            .help("Einen oder mehrere auswählen – z. B. wenn eine Datei mehrere Spektren enthält")
            .popover(isPresented: $show, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mehrfachauswahl möglich").font(.caption).foregroundStyle(.secondary)
                    ForEach(options, id: \.self) { option in
                        Toggle(isOn: Binding(get: { selected.contains(option) }, set: { set(option, $0) })) {
                            Text(verbatim: option)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(12)
            }
    }

    /// Hält die Reihenfolge der Vorschläge ein; eigene Einträge bleiben hinten erhalten.
    private func set(_ option: String, _ on: Bool) {
        var current = selected
        if on { if !current.contains(option) { current.append(option) } } else { current.removeAll { $0 == option } }
        let known = options.filter { current.contains($0) }
        let custom = current.filter { !options.contains($0) }
        text = (known + custom).joined(separator: ", ")
    }
}

/// Eine verknüpfte Datei: Name, Beschreibung, Öffnen, im Finder zeigen, entfernen.
private struct AnalysisFileRow: View {
    @Binding var file: AnalysisFile
    var onRemove: () -> Void

    private var exists: Bool { FileManager.default.fileExists(atPath: file.filePath) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: exists ? "doc.text.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(exists ? Color.secondary : Color.orange)
                .help(exists ? file.filePath : String(localized: "Datei nicht gefunden: \(file.filePath)"))
            Text(verbatim: (file.filePath as NSString).lastPathComponent)
                .lineLimit(1).truncationMode(.middle).frame(width: 170, alignment: .leading)
                .help(file.filePath)
            TextField("Beschreibung …", text: $file.description).textFieldStyle(.roundedBorder)
                .onChange(of: file.description) { _, newV in let f = applySmartFormatting(to: newV); if f != newV { file.description = f } }
            Button("Öffnen") { NSWorkspace.shared.open(URL(fileURLWithPath: file.filePath)) }
                .buttonStyle(.bordered).disabled(!exists)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.filePath)]) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless).disabled(!exists).help("Im Finder zeigen")
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain).help("Verknüpfung entfernen (die Datei bleibt erhalten)")
        }
        .padding(6)
        .background(Color(NSColor.textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}
