import AppKit
import SwiftUI

/// Einstellungen (⌘,): Allgemein (Sprache, Zeichenprogramm), Speicherort & Backups, gelöschte Ansätze, CAS-Datenbank.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            StorageSettingsView()
                .tabItem { Label("Speicherort & Backups", systemImage: "externaldrive") }
            DeletedExperimentsView()
                .tabItem { Label("Gelöschte Ansätze", systemImage: "trash") }
            CASDatabaseView()
                .tabItem { Label("CAS-Datenbank", systemImage: "flask") }
        }
        .frame(width: 640, height: 500)
    }
}

// MARK: - Allgemein

private struct GeneralSettingsView: View {
    @State private var language = AppLanguage.stored
    @AppStorage(DrawingApp.defaultsKey) private var drawingApp = DrawingApp.chemDraw.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Sprache", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .onChange(of: language) { _, new in AppLanguage.stored = new }
                Text("Standard ist Deutsch, unabhängig von der Sprache des Macs. Die Smart-Extract-Texterkennung versteht immer Deutsch und Englisch.")
                    .font(.caption).foregroundStyle(.secondary)
                if language != AppLanguage.current {
                    HStack {
                        Label("Die neue Sprache gilt nach einem Neustart von ChemJournal.", systemImage: "arrow.clockwise")
                            .font(.callout)
                        Spacer()
                        Button("Jetzt neu starten") { AppLanguage.relaunch() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section("Reaktionsgleichung") {
                Picker("Zeichenprogramm", selection: $drawingApp) {
                    ForEach(DrawingApp.allCases, id: \.self) { app in
                        Text(app.isInstalled ? app.displayName : String(localized: "\(app.displayName) (nicht installiert)"))
                            .tag(app.rawValue)
                    }
                }
                Text("Bestimmt die Knöpfe „In … zeichnen“ und „In … bearbeiten“ bei der Reaktionsgleichung. Das andere Programm erreichst du über das kleine + daneben. Eine gespeicherte Zeichnung öffnet sich immer in dem Programm, mit dem sie gezeichnet wurde. ReShiki ist kostenlos und quelloffen (reshiki.com).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Speicherort & Backups

private struct StorageSettingsView: View {
    @Environment(JournalStore.self) private var store
    @State private var backups: [BackupInfo] = []
    @State private var pendingMode: StorageMode?
    @State private var conflict: (experiments: Int, modified: Date?)?
    @State private var isSwitching = false
    @State private var message: String?
    @State private var restoreCandidate: BackupInfo?

    var body: some View {
        Form {
            Section {
                Picker("Speicherort", selection: Binding(get: { store.storageMode }, set: { requestSwitch(to: $0) })) {
                    ForEach(StorageMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(isSwitching)
                if isSwitching { ProgressView("Daten werden umgezogen …").controlSize(.small) }
                Text(store.storageMode == .iCloud
                     ? String(localized: "Journal, Versionen, Backups und CAS-Datenbank liegen in iCloud Drive › ChemJournal und sind auf allen deinen Macs mit derselben Apple-ID verfügbar. Änderungen anderer Macs werden automatisch übernommen, solange du hier nichts Ungespeichertes hast.")
                     : String(localized: "Alles bleibt auf diesem Mac. Mit „iCloud Drive“ sind die Daten zusätzlich in der Cloud gesichert und auf deinen anderen Macs verfügbar."))
                    .font(.caption).foregroundStyle(.secondary)
                if !AppPaths.isICloudAvailable {
                    Label("iCloud Drive ist auf diesem Mac nicht eingeschaltet (Systemeinstellungen › Apple-ID › iCloud).", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let date = store.lastExternalReload {
                    Text("Zuletzt Änderungen von einem anderen Mac übernommen: \(date.appFormatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Journal") { PathButton(url: store.paths.journalFile) }
                LabeledContent("Versionen") { PathButton(url: store.paths.versionsDirectory) }
                LabeledContent("Backups") { PathButton(url: store.paths.backupsDirectory) }
            }

            Section {
                HStack {
                    Text("Automatisch: ein Backup pro Tag (bleibt 30 Tage) und Versionen je Ansatz.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Jetzt sichern") {
                        Task {
                            let url = await store.backupNow()
                            message = url == nil ? String(localized: "Backup konnte nicht angelegt werden (noch keine Daten gespeichert?).") : String(localized: "Backup angelegt: \(url!.lastPathComponent)")
                            await reloadBackups()
                        }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if backups.isEmpty {
                    Text("Noch keine Backups – das erste entsteht bei der ersten Änderung heute.").foregroundStyle(.secondary)
                } else {
                    ForEach(backups.prefix(12)) { b in
                        HStack {
                            Image(systemName: b.url.lastPathComponent.contains("manuell") ? "hand.raised" : "calendar")
                                .foregroundStyle(.secondary).frame(width: 18)
                            Text(b.date.appFormatted(date: .abbreviated, time: .shortened)).monospacedDigit()
                            Text(ByteCountFormatter.string(fromByteCount: b.size, countStyle: .file)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([b.url]) }
                                .buttonStyle(.link)
                            Button("Wiederherstellen …") { restoreCandidate = b }
                                .buttonStyle(.link)
                        }
                    }
                    if backups.count > 12 { Text("+ \(backups.count - 12) ältere").font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("Beim Wiederherstellen wird der aktuelle Stand vorher selbst als Backup gesichert. Mit ⌘Z lässt es sich außerdem rückgängig machen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await reloadBackups() }
        .onChange(of: store.storageMode) { _, _ in Task { await reloadBackups() } }
        .confirmationDialog("Journal auf diesen Stand zurücksetzen?",
                            isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } }),
                            presenting: restoreCandidate) { b in
            Button("Wiederherstellen") { restore(b) }
            Button("Abbrechen", role: .cancel) { restoreCandidate = nil }
        } message: { b in
            Text("Das ganze Journal wird durch das Backup vom \(b.date.appFormatted(date: .abbreviated, time: .shortened)) ersetzt. Der aktuelle Stand wird vorher als Backup gesichert.")
        }
        .alert("In iCloud Drive liegt bereits ein Journal",
               isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil; pendingMode = nil } })) {
            Button("Vorhandenes Journal verwenden") { performSwitch(useExisting: true) }
            Button("Durch dieses Journal ersetzen") { performSwitch(useExisting: false) }
            Button("Abbrechen", role: .cancel) { conflict = nil; pendingMode = nil }
        } message: {
            if let conflict {
                let date = conflict.modified.map { String(localized: " (zuletzt geändert \($0.appFormatted(date: .abbreviated, time: .shortened)))") } ?? ""
                Text("Am Ziel gibt es schon ein Journal mit \(conflict.experiments) Ansätzen\(date), z. B. von einem anderen Mac. Die jeweils andere Fassung wird in jedem Fall als Backup aufbewahrt.")
            }
        }
    }

    private func reloadBackups() async { backups = await store.backups() }

    private func restore(_ backup: BackupInfo) {
        restoreCandidate = nil
        Task {
            switch await store.restoreBackup(backup) {
            case .restored(let safety):
                message = safety.map { String(localized: "Backup wiederhergestellt. Der vorherige Stand liegt unter \($0.lastPathComponent).") }
                    ?? String(localized: "Backup wiederhergestellt.")
            case .unreadable:
                message = String(localized: "Dieses Backup ist nicht lesbar und wurde nicht wiederhergestellt.")
            }
            await reloadBackups()
        }
    }

    private func requestSwitch(to mode: StorageMode) {
        guard mode != store.storageMode, !isSwitching else { return }
        Task {
            switch await store.checkSwitch(to: mode) {
            case .unavailable:
                message = String(localized: "iCloud Drive ist nicht verfügbar.")
            case .targetHasJournal(let n, let modified):
                pendingMode = mode
                conflict = (n, modified)
            case .ready:
                pendingMode = mode
                performSwitch(useExisting: false)
            }
        }
    }

    private func performSwitch(useExisting: Bool) {
        guard let mode = pendingMode else { return }
        conflict = nil
        isSwitching = true
        Task {
            await store.switchStorage(to: mode, useExistingJournal: useExisting)
            isSwitching = false
            pendingMode = nil
            message = String(localized: "Speicherort: \(mode.title). Die bisherigen Dateien am alten Ort bleiben unverändert liegen.")
            await reloadBackups()
        }
    }
}

/// Pfad (abgekürzt) mit Klick → Finder.
private struct PathButton: View {
    let url: URL
    var body: some View {
        Button {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            else { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
        } label: {
            Text((url.path as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1).truncationMode(.middle)
        }
        .buttonStyle(.link)
        .help("Im Finder zeigen")
    }
}

// MARK: - Gelöschte Ansätze

private struct DeletedExperimentsView: View {
    @Environment(JournalStore.self) private var store
    @State private var deleted: [VersionInfo] = []
    @State private var selectedID: VersionInfo.ID?
    @State private var snapshot: VersionSnapshot?
    @State private var confirmPurge = false

    private var selected: VersionInfo? { deleted.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            if deleted.isEmpty {
                ContentUnavailableView("Keine gelöschten Ansätze", systemImage: "trash.slash",
                                       description: Text("Gelöschte Ansätze bleiben hier mit ihrem letzten Stand, bis du sie endgültig entfernst."))
            } else {
                HSplitView {
                    List(deleted, selection: $selectedID) { info in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.title.isEmpty ? String(localized: "Ohne Titel") : info.title).lineLimit(1)
                            Text([info.projectTitle, info.date.appFormatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(info.id)
                    }
                    .frame(minWidth: 200, idealWidth: 220)
                    Group {
                        if let snapshot { VersionPreview(snapshot: snapshot) }
                        else { Text("Ansatz auswählen").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Button("Endgültig entfernen …", role: .destructive) { confirmPurge = true }
                    .disabled(selected == nil)
                Spacer()
                Button("Wiederherstellen") { restore() }
                    .disabled(snapshot == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .task { await reload() }
        .onChange(of: selectedID) { _, _ in Task { await loadSnapshot() } }
        .confirmationDialog("Verlauf dieses Ansatzes endgültig entfernen?", isPresented: $confirmPurge) {
            Button("Endgültig entfernen", role: .destructive) { purge() }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Alle gespeicherten Versionen dieses Ansatzes werden gelöscht. Tägliche Backups des ganzen Journals bleiben davon unberührt.")
        }
    }

    private func reload() async {
        store.saveNow()
        deleted = await store.deletedExperiments()
        if selected == nil { selectedID = deleted.first?.id }
    }

    private func loadSnapshot() async {
        guard let info = selected else { snapshot = nil; return }
        snapshot = nil
        let loaded = await store.snapshot(of: info)
        if selectedID == info.id { snapshot = loaded }
    }

    private func restore() {
        guard let snapshot else { return }
        let id = store.restore(snapshot, asCopy: false)
        NotificationCenter.default.post(name: .selectExperiment, object: id)
        selectedID = nil
        Task { await reload() }
    }

    private func purge() {
        guard let info = selected else { return }
        Task {
            await store.purgeHistory(for: info.experimentID)
            selectedID = nil
            await reload()
        }
    }
}

// MARK: - CAS-Datenbank

private struct CASDatabaseView: View {
    @State private var query = ""
    @State private var selection = Set<String>()
    private var db: CASDatabase { CASDatabase.shared }

    private var entries: [CASEntry] {
        let q = SearchText.normalize(query)
        guard !q.isEmpty else { return db.sortedEntries }
        return db.sortedEntries.filter { SearchText.normalize($0.name).contains(q) || $0.cas.contains(query.trimmingCharacters(in: .whitespaces)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jede eingegebene CAS-Nummer mit Molmasse und Dichte – aus PubChem oder von dir. Beim nächsten Eintippen der CAS-Nummer werden die Werte sofort eingetragen, auch offline. Eigene Werte haben Vorrang vor PubChem. Molmasse und Dichte lassen sich hier direkt ändern (Doppelklick oder Klick ins Feld, Return übernimmt).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Table(entries, selection: $selection) {
                TableColumn("CAS", value: \.cas).width(min: 80, ideal: 90)
                TableColumn("Name") { Text($0.name.isEmpty ? "–" : $0.name) }
                TableColumn("M (g/mol)") { e in
                    CASValueField(value: e.molarMass) { db.edit(cas: e.cas, molarMass: $0, density: e.density) }
                }.width(min: 60, ideal: 75)
                TableColumn("d (g/cm³)") { e in
                    CASValueField(value: e.density) { db.edit(cas: e.cas, molarMass: e.molarMass, density: $0) }
                }.width(min: 60, ideal: 75)
                TableColumn("Quelle") { e in
                    Text(e.source.displayName).foregroundStyle(e.source == .user ? .primary : .secondary)
                }.width(min: 70, ideal: 90)
                TableColumn("Datum") { Text($0.updatedAt.appFormatted(date: .numeric, time: .omitted)).monospacedDigit() }.width(min: 60, ideal: 75)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                Button("Entfernen") { ids.forEach { db.remove(cas: $0) } }
            }
            HStack {
                Text("\(db.entries.count) Einträge").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Ausgewählte entfernen") {
                    selection.forEach { db.remove(cas: $0) }
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
            }
        }
        .padding(16)
        .searchable(text: $query, placement: .toolbar, prompt: "CAS oder Name")
    }
}

/// Bearbeitbare Zahl in der CAS-Tabelle. Übernimmt bei Return oder beim Verlassen des Feldes.
private struct CASValueField: View {
    let value: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $text, prompt: Text(verbatim: "–")) { EmptyView() }
            .textFieldStyle(.plain)
            .monospacedDigit()
            .focused($focused)
            .onSubmit { commit(text) }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit(text) } }
            .onAppear { text = value }
            .onChange(of: value) { _, new in if !focused { text = new } }
            .help("Wert ändern – gilt danach als eigene Eingabe")
    }
}
