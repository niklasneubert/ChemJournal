import SwiftUI

/// Versionsverlauf eines Ansatzes: Liste links, Vorschau rechts, Wiederherstellen unten.
struct VersionHistoryView: View {
    let experimentID: UUID
    let currentTitle: String

    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [VersionInfo] = []
    @State private var selectedID: VersionInfo.ID?
    @State private var snapshot: VersionSnapshot?
    @State private var isLoading = true
    @State private var confirmRestore = false

    private var selected: VersionInfo? { versions.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verlauf").font(.headline)
                    Text(currentTitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if versions.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Versionen", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("ChemJournal sichert automatisch: beim ersten Speichern, danach höchstens alle 10 Minuten, wenn sich etwas geändert hat, und beim Beenden.")
                }
            } else {
                HSplitView {
                    List(versions, selection: $selectedID) { info in
                        VersionRow(info: info).tag(info.id)
                    }
                    .frame(minWidth: 230, idealWidth: 250, maxWidth: 320)

                    Group {
                        if let snapshot { VersionPreview(snapshot: snapshot) }
                        else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()
            HStack {
                Text("Ältere Versionen werden ausgedünnt: 24 h alle, 30 Tage eine pro Tag, danach eine pro Woche.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Als Kopie hinzufügen") { restore(asCopy: true) }
                    .disabled(snapshot == nil)
                    .help("Diese Version als zusätzlichen Ansatz einfügen – der aktuelle Stand bleibt unverändert")
                Button("Wiederherstellen …") { confirmRestore = true }
                    .disabled(snapshot == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 480, idealHeight: 560)
        .task { await load() }
        .onChange(of: selectedID) { _, _ in Task { await loadSnapshot() } }
        .confirmationDialog("Diesen Stand wiederherstellen?", isPresented: $confirmRestore) {
            Button("Wiederherstellen") { restore(asCopy: false) }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Der aktuelle Stand wird vorher selbst als Version gesichert und bleibt im Verlauf.")
        }
    }

    private func load() async {
        store.saveNow()   // laufende Änderungen zuerst auf die Platte
        versions = await store.versions(for: experimentID)
        isLoading = false
        selectedID = versions.first?.id
    }

    private func loadSnapshot() async {
        guard let info = selected else { snapshot = nil; return }
        snapshot = nil
        let loaded = await store.snapshot(of: info)
        if selectedID == info.id { snapshot = loaded }
    }

    private func restore(asCopy: Bool) {
        guard let snapshot else { return }
        let id = store.restore(snapshot, asCopy: asCopy)
        dismiss()
        if asCopy { NotificationCenter.default.post(name: .selectExperiment, object: id) }
    }
}

private struct VersionRow: View {
    let info: VersionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(info.date.formatted(date: .abbreviated, time: .shortened)).font(.body.monospacedDigit())
                if info.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange).help("Wird nie automatisch entfernt") }
            }
            Text(info.reason).font(.caption).foregroundStyle(.secondary)
            Text("\(info.stageCount) \(info.stageCount == 1 ? "Stufe" : "Stufen") · \(info.chemicalCount) Chemikalien")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Schreibgeschützte Kurzansicht eines gespeicherten Stands.
struct VersionPreview: View {
    let snapshot: VersionSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(snapshot.experiment.title.isEmpty ? "Ohne Titel" : snapshot.experiment.title).font(.title2.bold())
                if !snapshot.experiment.summary.isEmpty {
                    Text(snapshot.experiment.summary).foregroundStyle(.secondary)
                }
                if let project = snapshot.projectTitle {
                    Label(project, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(snapshot.experiment.stages) { stage in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stage.title).font(.headline)
                        if !stage.chemicals.isEmpty {
                            ForEach(stage.chemicals) { c in
                                Text(Self.line(name: c.name, cas: c.cas, values: [c.equivalents.isEmpty ? "" : "\(c.equivalents) eq", c.mass, c.volume, c.amount]))
                                    .font(.callout)
                            }
                        }
                        ForEach(stage.yieldProducts) { y in
                            Text("Produkt: " + Self.line(name: y.name, cas: y.cas, values: [y.mass, y.amount]))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if !stage.procedure.isEmpty {
                            Text(stage.procedure).font(.callout).foregroundStyle(.secondary).lineLimit(8)
                        }
                        if !stage.observation.isEmpty {
                            Text("Beobachtung: " + stage.observation).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(20)
            .textSelection(.enabled)
        }
    }

    private static func line(name: String, cas: String, values: [String]) -> String {
        var s = name.isEmpty ? "–" : name
        if !cas.isEmpty { s += " (\(cas))" }
        let v = values.filter { !$0.isEmpty }
        if !v.isEmpty { s += " · " + v.joined(separator: " · ") }
        return s
    }
}
