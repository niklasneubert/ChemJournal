import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// „Aufreinigung & Analytik“ einer Stufe: beliebig viele Einträge (NMR, IR, MS, Säule, Umkristallisation …), jeder mit
/// eigenem Formular und verknüpften Dateien.
struct AnalysisSectionView: View {
    @Binding var entries: [AnalysisEntry]
    /// Eintrag, der gerade am Farbstreifen gezogen wird, und die Rahmen aller Karten (zum Umsortieren).
    @State private var draggingID: UUID?
    @State private var cardFrames: [UUID: CGRect] = [:]
    /// Waagerechter Versatz beim Ziehen: nach rechts = unterordnen, nach links = herauslösen.
    @State private var dragOffsetX: CGFloat = 0
    private static let indentThreshold: CGFloat = 40

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
                if isVisible(entry) {
                AnalysisEntryCard(entry: $entry,
                                  onDuplicate: { duplicate(entry.id) },
                                  onMove: { move(entry.id, by: $0) },
                                  onDelete: { delete(entry.id) },
                                  canMoveUp: entries.first?.id != entry.id,
                                  canMoveDown: entries.last?.id != entry.id,
                                  isDragging: draggingID == entry.id,
                                  dragOffsetX: draggingID == entry.id ? dragOffsetX : 0,
                                  childCount: entries.filter { $0.parentID == entry.id }.count,
                                  nestTargets: nestTargets(for: entry),
                                  onNest: { nest(entry.id, under: $0) },
                                  onUnnest: { unnest(entry.id) },
                                  onReorderDrag: { y, dx in reorder(entry.id, pointerY: y, offsetX: dx) },
                                  onReorderEnd: { dx in finishDrag(entry.id, offsetX: dx) })
                    .padding(.leading, entry.parentID == nil ? 0 : 28)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: AnalysisCardFrameKey.self,
                                               value: [entry.id: geo.frame(in: .named(Self.space))])
                    })
                    .zIndex(draggingID == entry.id ? 1 : 0)
                }
            }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(AnalysisCardFrameKey.self) { cardFrames = $0 }
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

    /// Neuer, leerer Eintrag am Ende.
    private func add(_ method: AnalysisMethod) {
        withAnimation(.easeOut(duration: 0.15)) { entries.append(AnalysisEntry(method: method)) }
    }

    private func duplicate(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var copy = entries[i]
        copy.id = UUID(); copy.createdAt = Date(); copy.files = copy.files.map { var f = $0; f.id = UUID(); return f }
        // Kopie eines übergeordneten Eintrags hinter seine untergeordneten Einträge (ohne diese mitzukopieren)
        entries.insert(copy, at: blockRange(of: i, in: entries).upperBound)
        entries = AnalysisEntry.normalizedHierarchy(entries)
    }

    /// Löschen; untergeordnete Einträge bleiben als Einträge oberster Ebene erhalten.
    private func delete(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.15)) {
            for k in entries.indices where entries[k].parentID == id { entries[k].parentID = nil }
            entries.removeAll { $0.id == id }
        }
    }

    // MARK: Unterordnen

    private func isVisible(_ entry: AnalysisEntry) -> Bool {
        guard let p = entry.parentID, let parent = entries.first(where: { $0.id == p }) else { return true }
        return parent.isExpanded
    }

    /// Eintrag und seine untergeordneten Einträge (nur bei Einträgen oberster Ebene).
    private func blockRange(of i: Int, in list: [AnalysisEntry]) -> Range<Int> {
        var end = i + 1
        if list[i].parentID == nil { while end < list.count, list[end].parentID == list[i].id { end += 1 } }
        return i..<end
    }

    /// Mögliche übergeordnete Einträge: alle anderen Einträge oberster Ebene (nicht für Einträge mit eigenen Untereinträgen).
    private func nestTargets(for entry: AnalysisEntry) -> [(id: UUID, title: String)] {
        guard entry.parentID == nil, !entries.contains(where: { $0.parentID == entry.id }) else { return [] }
        return entries.filter { $0.parentID == nil && $0.id != entry.id }.map { e in
            let sample = e.sample.trimmingCharacters(in: .whitespaces)
            return (e.id, sample.isEmpty ? e.heading : "\(e.heading) – \(sample)")
        }
    }

    private func nest(_ id: UUID, under parentID: UUID) {
        withAnimation(.easeOut(duration: 0.2)) {
            guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
            var moving = entries.remove(at: i)
            moving.parentID = parentID
            guard let p = entries.firstIndex(where: { $0.id == parentID }) else { return }
            entries.insert(moving, at: blockRange(of: p, in: entries).upperBound)
            entries[entries.firstIndex(where: { $0.id == parentID })!].isExpanded = true
            entries = AnalysisEntry.normalizedHierarchy(entries)
        }
    }

    /// Herauslösen: als Eintrag oberster Ebene hinter den Block des bisherigen übergeordneten Eintrags.
    private func unnest(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) {
            guard let i = entries.firstIndex(where: { $0.id == id }), let parentID = entries[i].parentID else { return }
            var moving = entries.remove(at: i)
            moving.parentID = nil
            let insertAt = entries.firstIndex(where: { $0.id == parentID }).map { blockRange(of: $0, in: entries).upperBound } ?? i
            entries.insert(moving, at: insertAt)
            entries = AnalysisEntry.normalizedHierarchy(entries)
        }
    }

    /// Ende des Ziehens: deutlich nach rechts gezogen = unter den Eintrag darüber, nach links = herauslösen.
    private func finishDrag(_ id: UUID, offsetX: CGFloat) {
        defer { withAnimation(.easeOut(duration: 0.15)) { draggingID = nil; dragOffsetX = 0 } }
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        if offsetX > Self.indentThreshold, entries[i].parentID == nil, !entries.contains(where: { $0.parentID == id }),
           let parent = entries[..<i].last(where: { $0.parentID == nil }) {
            nest(id, under: parent.id)
        } else if offsetX < -Self.indentThreshold, entries[i].parentID != nil {
            unnest(id)
        }
    }

    static let space = "analysisSection"

    /// Umsortieren per Ziehen am Farbstreifen: Die gezogene Karte wandert an die Stelle, über der der Zeiger steht.
    /// Ein Eintrag oberster Ebene wandert mit seinen untergeordneten Einträgen; ein untergeordneter Eintrag gehört danach
    /// zum nächsten Eintrag oberster Ebene darüber.
    private func reorder(_ id: UUID, pointerY: CGFloat, offsetX: CGFloat) {
        if draggingID != id { withAnimation(.easeOut(duration: 0.12)) { draggingID = id } }
        dragOffsetX = offsetX
        guard let from = entries.firstIndex(where: { $0.id == id }) else { return }
        // Eingeklappte untergeordnete Einträge haben keinen Rahmen: Sie stehen an der Stelle ihres übergeordneten Eintrags
        func midY(_ e: AnalysisEntry) -> CGFloat { cardFrames[e.id]?.midY ?? e.parentID.flatMap { cardFrames[$0]?.midY } ?? .infinity }
        let block = blockRange(of: from, in: entries)
        var rest = entries
        let moving = Array(rest[block])
        rest.removeSubrange(block)
        var target = 0
        if entries[from].parentID == nil {
            // nur zwischen ganzen Blöcken einfügen
            var k = 0
            while k < rest.count {
                let r = blockRange(of: k, in: rest)
                if midY(rest[k]) < pointerY { target = r.upperBound }
                k = r.upperBound
            }
        } else {
            target = rest.filter { midY($0) < pointerY }.count
        }
        var result = rest
        result.insert(contentsOf: moving, at: target)
        if entries[from].parentID != nil {
            result[target].parentID = result[..<target].last(where: { $0.parentID == nil })?.id
        }
        result = AnalysisEntry.normalizedHierarchy(result)
        guard result.map(\.id) != entries.map(\.id) || result.map(\.parentID) != entries.map(\.parentID) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { entries = result }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries.indices.contains(i + offset) else { return }
        entries.swapAt(i, i + offset)
        entries = AnalysisEntry.normalizedHierarchy(entries)
    }
}

private struct AnalysisCardFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
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
    var isDragging = false
    var dragOffsetX: CGFloat = 0
    var childCount = 0
    var nestTargets: [(id: UUID, title: String)] = []
    var onNest: (UUID) -> Void = { _ in }
    var onUnnest: () -> Void = {}
    /// Zeigerposition (y im Koordinatenraum der Analytik) und waagerechter Versatz beim Ziehen am Farbstreifen.
    var onReorderDrag: (CGFloat, CGFloat) -> Void = { _, _ in }
    var onReorderEnd: (CGFloat) -> Void = { _ in }
    @State private var isDropTarget = false
    @State private var isHoveringHandle = false

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
        .overlay(alignment: .leading) { reorderHandle }
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isDropTarget ? Color.accentColor : Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: isDropTarget ? [6] : [])))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in linkDroppedFiles(providers) }
        .scaleEffect(isDragging ? 1.01 : 1)
        .offset(x: max(-30, min(30, dragOffsetX * 0.5)))
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: isDragging ? 10 : 0, y: isDragging ? 4 : 0)
    }

    /// Farbstreifen (blau = Spektroskopie, grün = Aufreinigung) – zugleich Griff zum Verschieben der Karte.
    private var reorderHandle: some View {
        let active = isHoveringHandle || isDragging
        return ZStack(alignment: .leading) {
            Color.clear.frame(width: 10)
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                .fill(entry.method.tint.opacity(active ? 0.95 : 0.7))
                .frame(width: active ? 6 : 3)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            isHoveringHandle = inside
            if !isDragging { (inside ? NSCursor.openHand : NSCursor.arrow).set() }
        }
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(AnalysisSectionView.space))
            .onChanged { value in
                NSCursor.closedHand.set()
                onReorderDrag(value.location.y, value.translation.width)
            }
            .onEnded { value in
                onReorderEnd(value.translation.width)
                (isHoveringHandle ? NSCursor.openHand : NSCursor.arrow).set()
            })
        .animation(.easeOut(duration: 0.12), value: active)
        .help("Gedrückt halten und ziehen, um die Reihenfolge zu ändern – nach rechts ziehen ordnet unter, nach links löst heraus")
        .accessibilityLabel("Eintrag verschieben")
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
            if !entry.isExpanded, childCount > 0 {
                Label("\(childCount)", systemImage: "list.bullet.indent").font(.caption).foregroundStyle(.secondary)
                    .help("Untergeordnete Einträge (eingeklappt)")
            }
            if !entry.isExpanded, !entry.files.isEmpty {
                Label("\(entry.files.count)", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary)
                    .help("Verknüpfte Dateien")
            }
            Menu {
                Button("Duplizieren", action: onDuplicate)
                Button("Nach oben") { onMove(-1) }.disabled(!canMoveUp)
                Button("Nach unten") { onMove(1) }.disabled(!canMoveDown)
                if entry.parentID != nil {
                    Button("Herauslösen", action: onUnnest)
                } else if !nestTargets.isEmpty {
                    Menu("Unterordnen unter") {
                        ForEach(nestTargets, id: \.id) { t in Button(t.title) { onNest(t.id) } }
                    }
                }
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
