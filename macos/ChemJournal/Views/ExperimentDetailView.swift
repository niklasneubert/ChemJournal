import SwiftUI

/// Detailansicht eines Ansatzes mit allen Stufen.
struct DetailView: View {
    @Binding var experiment: Experiment
    @State private var showHistory = false

    private var hasYields: Bool { experiment.stages.contains { !$0.yieldProducts.isEmpty } }
    private var contentNeededWidth: CGFloat { hasYields ? 960 : 780 }

    var body: some View {
        GeometryReader { scrollGeo in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Titel des Ansatzes", text: $experiment.title).font(.system(size: 32, weight: .bold)).textFieldStyle(.plain)
                        .onChange(of: experiment.title) { _, _ in experiment.updatedAt = Date() }
                    TextField("Kurze Zusammenfassung", text: $experiment.summary).font(.title3).foregroundColor(.secondary).textFieldStyle(.plain)
                        .onChange(of: experiment.summary) { _, _ in experiment.updatedAt = Date() }
                    HStack(spacing: 16) {
                        Label(experiment.createdAt.appFormatted(date: .long, time: .omitted), systemImage: "calendar")
                        Button { showHistory = true } label: { Label("Verlauf", systemImage: "clock.arrow.circlepath") }
                            .buttonStyle(.link)
                            .help("Frühere Versionen dieses Ansatzes ansehen und wiederherstellen")
                        MarkButton(isMarked: $experiment.isMarked)
                    }
                    .font(.caption).foregroundColor(.secondary)
                    ExperimentTagBar(experiment: $experiment)
                    Divider().padding(.vertical, 6)
                    ForEach($experiment.stages) { $stage in
                        StageView(stage: $stage,
                            onDelete: { experiment.stages.removeAll { $0.id == stage.id } },
                            duplicateAction: {
                                var copy = stage; copy.id = UUID(); copy.title = stage.title + String(localized: " (Kopie)"); copy.createdAt = Date()
                                if let idx = experiment.stages.firstIndex(where: { $0.id == stage.id }) {
                                    experiment.stages.insert(copy, at: experiment.stages.index(after: idx))
                                }
                            })
                    }
                    .onMove { from, to in experiment.stages.move(fromOffsets: from, toOffset: to) }
                    Button(action: { experiment.stages.append(Stage(title: String(localized: "Stufe \(experiment.stages.count + 1)"))) }) {
                        HStack { Image(systemName: "plus.circle.fill"); Text("Neue Stufe hinzufügen") }.font(.headline).foregroundColor(.blue).padding().frame(maxWidth: .infinity).background(Color.blue.opacity(0.1)).cornerRadius(10)
                    }.buttonStyle(.plain).padding(.top, 10)
                }
                .padding(30)
                // Feste Breite statt nur Mindestbreite: Der waagrechte ScrollView schlägt sonst keine Breite vor,
                // breite Bilder (z. B. aus ChemDraw) machen die Seite breiter als das Fenster und der Titel rutscht
                // unter die Symbolleiste.
                .frame(width: max(scrollGeo.size.width, contentNeededWidth), alignment: .leading)
            }
            .background(.regularMaterial)
            .sheet(isPresented: $showHistory) { VersionHistoryView(experimentID: experiment.id, currentTitle: experiment.title) }
            .onAppear { updateSnapWidths() }
            .onChange(of: hasYields) { _, _ in updateSnapWidths() }
        }
    }

    private func updateSnapWidths() {
        WindowSnapManager.shared.perfectWidth = 1024
        WindowSnapManager.shared.snapWidths = hasYields ? [1024, 1260] : [1024]
    }
}
