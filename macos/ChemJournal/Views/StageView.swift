import SwiftUI
import AppKit

struct StageView: View {
    @Binding var stage: Stage
    var onDelete: () -> Void
    var duplicateAction: () -> Void
    @State private var isEditingSource = false
    @State private var showDeleteConfirm = false
    /// Gehört zu genau dieser Stufe. Vorher öffnete eine Notification den Dialog in allen Stufen gleichzeitig.
    @State private var showSmartExtract = false

    @ViewBuilder
    func stageContextMenu(for textBinding: Binding<String>) -> some View {
        Button(action: { textBinding.wrappedValue = applySmartFormatting(to: textBinding.wrappedValue) }) { Label("Smarte Formatierung anwenden", systemImage: "textformat.subscript") }
        Divider()
        Button(action: { showSmartExtract = true }) { Label("Smart Extract (KI) öffnen", systemImage: "wand.and.stars") }
    }

    func extractURL(from text: String) -> URL? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("http") { return URL(string: clean) }
        if clean.lowercased().hasPrefix("doi:") { return URL(string: "https://doi.org/" + clean.dropFirst(4).trimmingCharacters(in: .whitespaces)) }
        if clean.lowercased().hasPrefix("10.") { return URL(string: "https://doi.org/" + clean) }
        return nil
    }

    var body: some View {
        DisclosureGroup(isExpanded: $stage.isExpanded) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Quelle:").font(.headline)
                    if !isEditingSource, let url = extractURL(from: stage.sourceURL) {
                        Link(stage.sourceURL, destination: url).foregroundColor(.blue).lineLimit(1)
                        Spacer()
                        Button(action: { isEditingSource = true }) { Image(systemName: "pencil").foregroundColor(.gray) }.buttonStyle(.plain)
                    } else {
                        TextField("DOI, URL oder Buch...", text: $stage.sourceURL).textFieldStyle(.roundedBorder).onSubmit { isEditingSource = false }
                        if extractURL(from: stage.sourceURL) != nil { Button(action: { isEditingSource = false }) { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }.buttonStyle(.plain) }
                    }
                }
                LaTeXEditorView(title: "Zusammenfassung", text: $stage.summary).contextMenu { stageContextMenu(for: $stage.summary) }
                ReactionImageView(imageData: $stage.reactionImageData)
                ChemicalTableView(chemicals: $stage.chemicals, showSmartExtract: $showSmartExtract)
                LaTeXEditorView(title: "Vorgehen", text: $stage.procedure).contextMenu { stageContextMenu(for: $stage.procedure) }
                LaTeXEditorView(title: "Beobachtung", text: $stage.observation).contextMenu { stageContextMenu(for: $stage.observation) }
                YieldTableView(yields: $stage.yieldProducts, allChemicals: $stage.chemicals)
                AnalysisFilesView(filePaths: $stage.analysisFiles)
            }.padding(.top, 10).padding(.bottom, 20)
        } label: {
            HStack {
                TextField("Stufenname", text: $stage.title).font(.title2).fontWeight(.semibold)
                Spacer()
                // Jede Stufe zeigt ihr eigenes Datum (eine spätere Stufe also den Tag, an dem sie angelegt wurde)
                Label(stage.createdAt.appFormatted(date: .long, time: .omitted), systemImage: "calendar")
                    .font(.caption).foregroundColor(.secondary).fixedSize()
                    .help(String(localized: "Stufe angelegt am \(stage.createdAt.appFormatted(date: .long, time: .shortened))"))
                Button(action: duplicateAction) { Image(systemName: "doc.on.doc").foregroundColor(.blue) }.buttonStyle(.plain)
                Button(action: { showDeleteConfirm = true }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain)
            }
        }
        .padding().background(Color(NSColor.windowBackgroundColor).opacity(0.6)).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1)).padding(.bottom, 10)
        .confirmationDialog("Stufe löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Stufe löschen", role: .destructive) { onDelete() }
            Button("Abbrechen", role: .cancel) { }
        } message: { Text("Alle Daten dieser Stufe werden gelöscht. Mit ⌘Z lässt sich das rückgängig machen.") }
    }
}
