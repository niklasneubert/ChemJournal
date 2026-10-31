import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Hauptansicht
struct ContentView: View {
    @Environment(JournalStore.self) private var store
    /// Menübefehle nur im aktiven Fenster ausführen – sonst legt jedes offene Fenster einen eigenen Ansatz an.
    @Environment(\.appearsActive) private var appearsActive
    @State private var selection: SidebarItem?
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var showExportDialog = false
    @State private var exportExperiments: [Experiment] = []
    @State private var exportProjectName: String = ""
    @State private var isExporting = false
    @State private var showExportError = false
    /// Filter der Seitenleiste: nur markierte Ansätze und/oder nur Ansätze mit diesem Tag.
    @State private var filterMarked = false
    @State private var filterTag: String?

    private var projects: [Project] {
        get { store.projects }
        nonmutating set { store.projects = newValue }
    }

    /// Letztes Suchergebnis. Die Seitenleiste wird oft neu gezeichnet (Auswahl, Filter, Mausbewegung), ohne dass
    /// sich Suchbegriff oder Daten ändern – dann muss die Suche nicht erneut über das ganze Journal laufen.
    @State private var searchCache = SearchResultCache()

    /// Gefilterte Projekte und, je Ansatz, die getroffenen Chemikalien (für die Anzeige unter dem Titel).
    private var searchResults: (projects: [Project], hits: [UUID: [SearchHit]]) {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return (projects, [:]) }
        let casEntries = CASDatabase.shared.entries
        if let cached = searchCache.result(query: query, projects: projects, casEntries: casEntries) { return cached }
        let result = computeSearchResults(query: query)
        searchCache.store(result, query: query, projects: projects, casEntries: casEntries)
        return result
    }

    private func computeSearchResults(query: String) -> (projects: [Project], hits: [UUID: [SearchHit]]) {
        let search = JournalSearch(query: query, projects: projects, casDatabase: CASDatabase.shared)
        var hits: [UUID: [SearchHit]] = [:]
        let filtered: [Project] = projects.compactMap { project in
            let projectMatches = project.title.lowercased().contains(query.lowercased())
            var matching: [Experiment] = []
            for experiment in project.experiments {
                if let h = search.hits(in: experiment) { matching.append(experiment); hits[experiment.id] = h }
            }
            if !projectMatches && matching.isEmpty { return nil }
            var fp = project; if !projectMatches { fp.experiments = matching }; return fp
        }
        return (filtered, hits)
    }

    private var allTags: [String] { JournalTag.all(in: projects) }
    private var isFiltering: Bool { filterMarked || filterTag != nil }

    private func passesFilter(_ e: Experiment) -> Bool {
        (!filterMarked || e.isMarked) && (filterTag.map { e.hasTag($0) } ?? true)
    }

    /// Suchergebnis zusätzlich nach Markierung und Tag gefiltert; Projekte ohne passenden Ansatz fallen weg.
    private var filteredResults: (projects: [Project], hits: [UUID: [SearchHit]]) {
        let results = searchResults
        guard isFiltering else { return results }
        let filtered: [Project] = results.projects.compactMap { project in
            var fp = project
            fp.experiments = project.experiments.filter(passesFilter)
            return fp.experiments.isEmpty ? nil : fp
        }
        return (filtered, results.hits)
    }

    private func clearFilter() { filterMarked = false; filterTag = nil }

    var body: some View {
        @Bindable var store = store
        let results = filteredResults
        let tags = allTags
        NavigationSplitView {
            List(selection: $selection) {
                if isFiltering && results.projects.isEmpty {
                    Text("Keine Ansätze für diesen Filter").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(results.projects) { project in
                    let isExpandedBinding = Binding<Bool>(
                        get: { projects.first(where: { $0.id == project.id })?.isExpanded ?? false },
                        set: { newVal in if let idx = projects.firstIndex(where: { $0.id == project.id }) { projects[idx].isExpanded = newVal } }
                    )
                    DisclosureGroup(isExpanded: isExpandedBinding) {
                        ForEach(project.experiments) { experiment in
                            NavigationLink(value: SidebarItem.experiment(experiment.id)) {
                                VStack(alignment: .leading) {
                                    HStack(spacing: 4) {
                                        Text(experiment.title.isEmpty ? String(localized: "Unbenannter Ansatz") : experiment.title).font(.headline)
                                        if experiment.isMarked {
                                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                                                .accessibilityLabel("Markiert")
                                        }
                                    }
                                    Text(experiment.summary.isEmpty ? String(localized: "Keine Beschreibung") : experiment.summary).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                                    Text(experiment.createdAt.appFormatted(date: .long, time: .omitted)).font(.caption2).foregroundColor(.secondary)
                                    if !experiment.tags.isEmpty {
                                        HStack(spacing: 4) {
                                            ForEach(experiment.tags.prefix(3), id: \.self) { TagChip(name: $0, compact: true) }
                                            if experiment.tags.count > 3 {
                                                Text(verbatim: "+\(experiment.tags.count - 3)").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.top, 1)
                                    }
                                    if let hits = results.hits[experiment.id], !hits.isEmpty {
                                        ForEach(hits.prefix(3), id: \.self) { hit in
                                            Label(hit.label, systemImage: "magnifyingglass").font(.caption2).foregroundStyle(.tint).lineLimit(1)
                                        }
                                        if hits.count > 3 { Text("+ \(hits.count - 3) weitere Treffer").font(.caption2).foregroundStyle(.secondary) }
                                    }
                                }.padding(.vertical, 4)
                            }
                            .draggable(experiment.id.uuidString)
                            .contextMenu {
                                Button(action: { updateExperiment(experiment.id) { $0.isMarked.toggle() } }) {
                                    Label(experiment.isMarked ? "Markierung entfernen" : "Markieren",
                                          systemImage: experiment.isMarked ? "star.slash" : "star")
                                }
                                Menu {
                                    ForEach(tags, id: \.self) { tag in
                                        Button(action: { toggleTag(tag, on: experiment.id) }) {
                                            if experiment.hasTag(tag) { Label(tag, systemImage: "checkmark") } else { Text(verbatim: tag) }
                                        }
                                    }
                                    if !tags.isEmpty { Divider() }
                                    Button("Neuer Tag …") { addNewTag(to: experiment.id) }
                                } label: { Label("Tags", systemImage: "tag") }
                                Divider()
                                Button(action: { duplicateExperiment(id: experiment.id) }) { Label("Ansatz duplizieren", systemImage: "doc.on.doc") }
                                Button(action: { exportExperimentAsFile(id: experiment.id) }) { Label("Als .chemjournal exportieren", systemImage: "square.and.arrow.up") }
                                Divider()
                                Button(role: .destructive, action: { deleteExperiment(id: experiment.id) }) { Label("Ansatz löschen", systemImage: "trash") }
                            }
                        }
                        // Während Suche oder Filter zeigen die Indizes auf die gefilterte Liste – Verschieben würde den falschen Ansatz treffen
                        .onMove(perform: searchText.isEmpty && !isFiltering ? { indices, newOffset in
                            if let pIdx = projects.firstIndex(where: { $0.id == project.id }) {
                                projects[pIdx].experiments.move(fromOffsets: indices, toOffset: newOffset)
                            }
                        } : nil)
                    } label: {
                        NavigationLink(value: SidebarItem.project(project.id)) {
                            Label(project.title, systemImage: "folder").font(.headline).padding(.vertical, 4)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let idString = items.first, let expID = UUID(uuidString: idString) else { return false }
                            return moveExperiment(experimentID: expID, toProjectID: project.id)
                        }
                        .contextMenu {
                            Button(role: .destructive, action: { deleteProject(id: project.id) }) { Label("Projekt löschen", systemImage: "trash") }
                        }
                    }
                }
            }
            // Liste bei jedem Suchbegriff neu aufbauen: Beim Filtern während des Tippens blieben sonst Zeilen aus
            // halb fertigen Übergängen übereinander stehen (Treffer doppelt gezeichnet). Die neue Liste würde den
            // Fokus übernehmen – deshalb geht er ans Suchfeld zurück.
            .id("\(searchText)|\(filterMarked)|\(filterTag ?? "")")
            .safeAreaInset(edge: .top) {
                if isFiltering { filterBanner }
            }
            .searchable(text: $searchText, prompt: "Suchen: Ansatz, Chemikalie, CAS …")
            .searchFocused($searchFieldFocused)
            .onChange(of: searchText) { _, _ in
                guard searchFieldFocused else { return }
                DispatchQueue.main.async { searchFieldFocused = true }
            }
            .scrollContentBackground(.hidden).background(.ultraThinMaterial)
            .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 400)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Menu {
                        Button(action: addProject) { Label("Neues Projekt", systemImage: "folder.badge.plus") }
                        Button(action: addExperiment) { Label("Neuer Ansatz", systemImage: "doc.badge.plus") }
                        Divider()
                        Button(action: importExperimentFromFile) { Label("Ansatz importieren (.chemjournal)", systemImage: "square.and.arrow.down") }
                    } label: {
                        // Label statt nur Symbol: bei „Symbol und Text“ (Rechtsklick auf die Symbolleiste) erscheint der Name
                        Label("Neu", systemImage: "plus")
                    }
                    .help("Neues Projekt, neuer Ansatz oder Ansatz importieren")
                    filterMenu(tags: tags)
                }
            }
        } detail: {
            ZStack {
                switch selection {
                case .project(let pid):
                    if let pIndex = projects.firstIndex(where: { $0.id == pid }) { ProjectDetailView(project: $store.projects[pIndex]) { addExperiment() } }
                case .experiment(let eid):
                    if let pIndex = projects.firstIndex(where: { $0.experiments.contains(where: { $0.id == eid }) }),
                       let eIndex = projects[pIndex].experiments.firstIndex(where: { $0.id == eid }) { DetailView(experiment: $store.projects[pIndex].experiments[eIndex]) }
                case nil: Text("Wähle ein Projekt oder einen Ansatz aus, oder erstelle ein neues.").font(.title2).foregroundColor(.secondary)
                }
                if isExporting {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack { ProgressView().scaleEffect(1.5).padding(.bottom); Text("PDF wird generiert...").font(.headline).foregroundColor(.white) }
                        .padding(30).background(.ultraThinMaterial).cornerRadius(16)
                }
            }
        }
        .task { await store.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .newExperiment)) { _ in if appearsActive { addExperiment() } }
        .onReceive(NotificationCenter.default.publisher(for: .newProject)) { _ in if appearsActive { addProject() } }
        .onReceive(NotificationCenter.default.publisher(for: .saveJournal)) { _ in if appearsActive { store.saveNow() } }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in if appearsActive { preparePDFExport() } }
        .onReceive(NotificationCenter.default.publisher(for: .importChemjournal)) { _ in if appearsActive { importExperimentFromFile() } }
        .onReceive(NotificationCenter.default.publisher(for: .filterByTag)) { note in
            if appearsActive, let tag = note.object as? String { filterTag = tag }
        }
        .onChange(of: allTags) { _, tags in
            // Tag umbenannt oder gelöscht: Filter darauf aufheben
            if let t = filterTag, !tags.contains(where: { JournalTag.same($0, t) }) { filterTag = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectExperiment)) { note in
            // Wiederhergestellter Ansatz (Verlauf oder Einstellungen) – nur im vordersten Fenster auswählen
            if appearsActive, let id = note.object as? UUID { selection = .experiment(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapToOptimalWidth)) { _ in
            if appearsActive { WindowSnapManager.shared.snapToPerfectWidth() }
        }
        .onChange(of: selection) { _, newSel in
            if case .experiment = newSel {
                // Wird in DetailView abhängig vom Inhalt gesetzt
            } else {
                WindowSnapManager.shared.updateSnapWidth(1024)
            }
        }
        .background(WindowSnapAccessor())
        .confirmationDialog("Wie möchtest du die Ansätze exportieren?", isPresented: $showExportDialog, titleVisibility: .visible) {
            Button("Als ein gemeinsames PDF") { executePDFExport(combined: true) }
            Button("Als getrennte Einzel-PDFs") { executePDFExport(combined: false) }
            Button("Abbrechen", role: .cancel) { }
        }
        .alert("PDF-Export fehlgeschlagen", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Das PDF konnte nicht erstellt werden. Bitte versuche es erneut.")
        }
        .alert("Hinweis zu deinen Daten", isPresented: Binding(get: { store.loadMessage != nil }, set: { if !$0 { store.loadMessage = nil } })) {
            Button("OK", role: .cancel) { store.loadMessage = nil }
        } message: {
            Text(store.loadMessage ?? "")
        }
    }

    // MARK: - Markierung, Tags, Filter

    private func filterMenu(tags: [String]) -> some View {
        Menu {
            Toggle(isOn: $filterMarked) { Label("Nur markierte", systemImage: "star") }
            if !tags.isEmpty {
                Divider()
                Picker("Tag", selection: $filterTag) {
                    Text("Alle Tags").tag(String?.none)
                    ForEach(tags, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
                }
                .pickerStyle(.inline)
            }
            if isFiltering {
                Divider()
                Button("Filter aufheben", action: clearFilter)
            }
        } label: {
            Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Ansätze nach Markierung oder Tag filtern")
    }

    private var filterBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(.tint)
            if filterMarked {
                Label("Markiert", systemImage: "star.fill").foregroundStyle(.secondary)
            }
            if let tag = filterTag { TagChip(name: tag, compact: true) }
            Spacer(minLength: 4)
            Button(action: clearFilter) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Filter aufheben")
                .accessibilityLabel("Filter aufheben")
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }

    private func updateExperiment(_ id: UUID, _ change: (inout Experiment) -> Void) {
        guard let p = projects.firstIndex(where: { $0.experiments.contains(where: { $0.id == id }) }),
              let e = projects[p].experiments.firstIndex(where: { $0.id == id }) else { return }
        change(&projects[p].experiments[e])
        projects[p].experiments[e].updatedAt = Date()
    }

    private func toggleTag(_ tag: String, on id: UUID) {
        updateExperiment(id) { exp in
            if exp.hasTag(tag) { exp.removeTag(tag) } else { exp.addTag(tag) }
        }
    }

    private func addNewTag(to id: UUID) {
        guard let name = TagPrompt.askName(title: String(localized: "Neuer Tag"),
                                           message: String(localized: "Name des Tags, z. B. „Photokatalyse“ oder „Scale-up“."),
                                           confirm: String(localized: "Hinzufügen")) else { return }
        let tag = allTags.first { JournalTag.same($0, name) } ?? name
        updateExperiment(id) { $0.addTag(tag) }
    }

    // MARK: - Navigation
    func addProject() { let p = Project(title: String(localized: "Neues Projekt")); projects.append(p); selection = .project(p.id) }

    func addExperiment() {
        if projects.isEmpty { addProject() }
        let newExp = Experiment(title: String(localized: "Neuer Ansatz"), summary: "")
        let pIdx = targetProjectIndex()
        projects[pIdx].experiments.append(newExp); projects[pIdx].isExpanded = true
        selection = .experiment(newExp.id)
    }

    /// Projekt der aktuellen Auswahl, sonst das erste.
    private func targetProjectIndex() -> Int {
        if case .project(let pid) = selection, let pIdx = projects.firstIndex(where: { $0.id == pid }) { return pIdx }
        if case .experiment(let eid) = selection, let pIdx = projects.firstIndex(where: { $0.experiments.contains(where: { $0.id == eid }) }) { return pIdx }
        return 0
    }

    func moveExperiment(experimentID: UUID, toProjectID: UUID) -> Bool {
        guard let oldIdx = projects.firstIndex(where: { $0.experiments.contains(where: { $0.id == experimentID }) }),
              projects[oldIdx].id != toProjectID,
              let newIdx = projects.firstIndex(where: { $0.id == toProjectID }),
              let exp = projects[oldIdx].experiments.first(where: { $0.id == experimentID }) else { return false }
        // Erst prüfen, dann verschieben – vorher konnte ein Ansatz verloren gehen, wenn das Zielprojekt fehlte
        projects[oldIdx].experiments.removeAll { $0.id == experimentID }
        projects[newIdx].experiments.append(exp)
        return true
    }

    func deleteProject(id: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == id }) else { return }
        let name = projects[pIdx].title
        let count = projects[pIdx].experiments.count
        let alert = NSAlert()
        alert.messageText = String(localized: "Projekt „\(name)“ löschen?")
        alert.informativeText = String(localized: "Alle \(count) Ansätze in diesem Projekt werden gelöscht. Sie bleiben im Versionsverlauf und lassen sich unter Einstellungen › Gelöschte Ansätze wiederherstellen.")
        alert.alertStyle = .warning; alert.addButton(withTitle: String(localized: "Löschen")); alert.addButton(withTitle: String(localized: "Abbrechen"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for exp in projects[pIdx].experiments { store.recordBeforeDeletion(exp, in: projects[pIdx]) }
        if case .project(let sid) = selection, sid == id { selection = nil }
        if case .experiment(let eid) = selection, projects[pIdx].experiments.contains(where: { $0.id == eid }) { selection = nil }
        projects.remove(at: pIdx)
    }

    func deleteExperiment(id: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.experiments.contains(where: { $0.id == id }) }),
              let eIdx = projects[pIdx].experiments.firstIndex(where: { $0.id == id }) else { return }
        let name = projects[pIdx].experiments[eIdx].title
        let alert = NSAlert()
        alert.messageText = String(localized: "Ansatz „\(name)“ löschen?")
        alert.informativeText = String(localized: "Der Ansatz bleibt im Versionsverlauf und lässt sich unter Einstellungen › Gelöschte Ansätze wiederherstellen.")
        alert.alertStyle = .warning; alert.addButton(withTitle: String(localized: "Löschen")); alert.addButton(withTitle: String(localized: "Abbrechen"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.recordBeforeDeletion(projects[pIdx].experiments[eIdx], in: projects[pIdx])
        if case .experiment(let sid) = selection, sid == id { selection = nil }
        projects[pIdx].experiments.remove(at: eIdx)
    }

    func duplicateExperiment(id: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.experiments.contains(where: { $0.id == id }) }),
              let exp = projects[pIdx].experiments.first(where: { $0.id == id }) else { return }
        var copy = exp; copy.id = UUID(); copy.title = exp.title + String(localized: " (Kopie)"); copy.createdAt = Date(); copy.updatedAt = Date()
        copy.stages = exp.stages.map { s in var ns = s; ns.id = UUID(); ns.createdAt = Date(); return ns }
        projects[pIdx].experiments.append(copy)
        selection = .experiment(copy.id)
    }

    func exportExperimentAsFile(id: UUID) {
        guard let exp = projects.flatMap(\.experiments).first(where: { $0.id == id }),
              let data = try? JSONEncoder().encode(exp) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.chemjournal]
        panel.nameFieldStringValue = "\(safeFileName(exp.title)).chemjournal"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }

    func importExperimentFromFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.chemjournal]; panel.allowsMultipleSelection = false
        panel.message = String(localized: "Wähle eine .chemjournal-Datei zum Importieren")
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              var exp = try? JSONDecoder().decode(Experiment.self, from: data) else { return }
        exp.id = UUID(); exp.title = exp.title + String(localized: " (importiert)")
        if projects.isEmpty { addProject() }
        let targetPIdx = targetProjectIndex()
        projects[targetPIdx].experiments.append(exp); projects[targetPIdx].isExpanded = true
        selection = .experiment(exp.id)
    }

    // MARK: - PDF Export
    private func preparePDFExport() {
        switch selection {
        case .experiment(let eid):
            if let exp = projects.flatMap({ $0.experiments }).first(where: { $0.id == eid }) {
                exportExperiments = [exp]
                exportProjectName = projects.first(where: { $0.experiments.contains(where: { $0.id == eid }) })?.title ?? ""
                executePDFExport(combined: true)
            }
        case .project(let pid):
            if let proj = projects.first(where: { $0.id == pid }), !proj.experiments.isEmpty {
                exportExperiments = proj.experiments; exportProjectName = proj.title; showExportDialog = true
            }
        case nil: break
        }
    }

    private func executePDFExport(combined: Bool) {
        guard !exportExperiments.isEmpty else { return }
        isExporting = true
        if combined {
            let html = HTMLGenerator.generate(for: exportExperiments, projectName: exportProjectName)
            let footer = self.exportProjectName.isEmpty ? (self.exportExperiments.first?.title ?? "") : self.exportProjectName
            PDFManager.shared.generatePDF(from: html, footer: footer) { pdfData in
                self.isExporting = false
                guard let pdfData = pdfData else { self.showExportError = true; return }
                let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = self.exportExperiments.count == 1 ? "\(safeFileName(self.exportExperiments[0].title)).pdf" : String(localized: "Laborjournal_Export") + ".pdf"
                if panel.runModal() == .OK, let url = panel.url { try? pdfData.write(to: url) }
            }
        } else {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            panel.message = String(localized: "Wähle den Ordner für den Export der einzelnen PDFs")
            if panel.runModal() == .OK, let folderURL = panel.url { exportNext(index: 0, folder: folderURL) }
            else { isExporting = false }
        }
    }

    private func exportNext(index: Int, folder: URL) {
        if index >= exportExperiments.count { self.isExporting = false; return }
        let exp = exportExperiments[index]
        PDFManager.shared.generatePDF(from: HTMLGenerator.generate(for: [exp], projectName: exportProjectName), footer: exp.title) { pdfData in
            if let pdfData = pdfData { try? pdfData.write(to: folder.appendingPathComponent("\(safeFileName(exp.title)).pdf")) }
            self.exportNext(index: index + 1, folder: folder)
        }
    }
}

#Preview { ContentView().environment(JournalStore(inMemory: true)) }

/// Merkt sich das letzte Suchergebnis samt Eingaben. Gleichheit der Projekte ist schnell: unveränderte Ansätze teilen
/// sich den Speicher, der Vergleich bricht beim ersten Unterschied ab.
final class SearchResultCache {
    private var query = ""
    private var projects: [Project] = []
    private var casEntries: [String: CASEntry] = [:]
    private var result: (projects: [Project], hits: [UUID: [SearchHit]])?

    func result(query: String, projects: [Project], casEntries: [String: CASEntry]) -> (projects: [Project], hits: [UUID: [SearchHit]])? {
        guard let result, query == self.query, casEntries == self.casEntries, projects == self.projects else { return nil }
        return result
    }

    func store(_ result: (projects: [Project], hits: [UUID: [SearchHit]]), query: String, projects: [Project], casEntries: [String: CASEntry]) {
        self.result = result
        self.query = query
        self.projects = projects
        self.casEntries = casEntries
    }
}
