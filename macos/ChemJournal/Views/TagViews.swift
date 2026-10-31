import SwiftUI
import AppKit

/// Feste Farbe pro Tag-Name (gleicher Name → gleiche Farbe, auch nach Neustart).
enum TagColor {
    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown, .mint, .red, .cyan]

    static func color(for tag: String) -> Color {
        let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        // Eigener Hash: `hashValue` ändert sich bei jedem Programmstart
        let sum = key.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return palette[Int(sum % UInt32(palette.count))]
    }
}

/// Farbige Kapsel mit dem Tag-Namen, optional mit Entfernen-Knopf.
struct TagChip: View {
    let name: String
    var compact = false
    var onRemove: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        let color = TagColor.color(for: name)
        HStack(spacing: 3) {
            Text(verbatim: name).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain)
                    .opacity(hovering ? 1 : 0.5)
                    .help("Tag von diesem Ansatz entfernen")
                    .accessibilityLabel("Tag \(name) entfernen")
            }
        }
        .font(compact ? .caption2 : .caption).fontWeight(.medium)
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 5 : 7).padding(.vertical, compact ? 1 : 3)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
        .onHover { hovering = $0 }
    }
}

/// Ordnet Elemente nebeneinander an und bricht um, wenn die Zeile voll ist.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty { rows.append(Row()) }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// Kleine Eingabedialoge für Tag-Namen.
enum TagPrompt {
    /// Fragt nach einem Namen; `nil` bei Abbrechen oder leerer Eingabe.
    @MainActor
    static func askName(title: String, message: String, defaultValue: String = "", confirm: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: defaultValue)
        field.placeholderString = String(localized: "Name des Tags")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return JournalTag.clean(field.stringValue)
    }

    @MainActor
    static func confirmDelete(_ tag: String, count: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Tag „\(tag)“ überall löschen?")
        alert.informativeText = String(localized: "Der Tag wird von \(count) Ansätzen entfernt. Die Ansätze selbst bleiben erhalten.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Löschen"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Markierung und Tags im Kopf eines Ansatzes: Tags anzeigen, hinzufügen, entfernen, überall umbenennen oder löschen.
struct ExperimentTagBar: View {
    @Binding var experiment: Experiment
    @Environment(JournalStore.self) private var store
    @State private var showAdd = false
    @State private var newTag = ""

    private var allTags: [String] { JournalTag.all(in: store.projects) }
    private var suggestions: [String] {
        let typed = newTag.trimmingCharacters(in: .whitespaces)
        return allTags.filter { tag in
            !experiment.hasTag(tag) && (typed.isEmpty || tag.localizedCaseInsensitiveContains(typed))
        }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(experiment.tags, id: \.self) { tag in
                TagChip(name: tag, onRemove: { remove(tag) })
                    .contextMenu {
                        Button("Nur Ansätze mit diesem Tag zeigen") {
                            NotificationCenter.default.post(name: .filterByTag, object: tag)
                        }
                        Divider()
                        Button("Umbenennen …") { rename(tag) }
                        Button("Von diesem Ansatz entfernen") { remove(tag) }
                        Button("Überall löschen …", role: .destructive) { deleteEverywhere(tag) }
                    }
            }
            Button { newTag = ""; showAdd = true } label: {
                Label(experiment.tags.isEmpty ? "Tag hinzufügen" : "Tag", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Eigenen Tag vergeben, um Ansätze einzuordnen")
            .popover(isPresented: $showAdd, arrowEdge: .bottom) { addPopover }
        }
    }

    private var addPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Neuer oder vorhandener Tag", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { add(newTag) }
            if !suggestions.isEmpty {
                Text("Vorhandene Tags").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button { add(tag) } label: { TagChip(name: tag) }.buttonStyle(.plain)
                    }
                }
                .frame(width: 240, alignment: .leading)
            }
            Text("Return übernimmt den Namen. Tags gelten für das ganze Journal.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private func add(_ raw: String) {
        defer { newTag = ""; showAdd = false }
        guard let typed = JournalTag.clean(raw) else { return }
        // Gleicher Name in anderer Schreibweise: die vorhandene übernehmen
        let tag = allTags.first { JournalTag.same($0, typed) } ?? typed
        if experiment.addTag(tag) { experiment.updatedAt = Date() }
    }

    private func remove(_ tag: String) {
        experiment.removeTag(tag)
        experiment.updatedAt = Date()
    }

    private func rename(_ tag: String) {
        guard let new = TagPrompt.askName(title: String(localized: "Tag „\(tag)“ umbenennen"),
                                          message: String(localized: "Der neue Name gilt in allen Ansätzen mit diesem Tag."),
                                          defaultValue: tag, confirm: String(localized: "Umbenennen")) else { return }
        JournalTag.rename(tag, to: new, in: &store.projects)
    }

    private func deleteEverywhere(_ tag: String) {
        let count = store.projects.flatMap(\.experiments).filter { $0.hasTag(tag) }.count
        guard TagPrompt.confirmDelete(tag, count: count) else { return }
        JournalTag.delete(tag, in: &store.projects)
    }
}

/// Stern-Knopf zum Markieren eines Ansatzes.
struct MarkButton: View {
    @Binding var isMarked: Bool

    var body: some View {
        Button { isMarked.toggle() } label: {
            Label(isMarked ? "Markiert" : "Markieren", systemImage: isMarked ? "star.fill" : "star")
                .foregroundStyle(isMarked ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(isMarked ? "Markierung entfernen" : "Ansatz markieren")
    }
}
