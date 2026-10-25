import SwiftUI
import AppKit

/// Verknüpfte Analysedateien (NMR, MS, …) einer Stufe.
struct AnalysisFilesView: View {
    @Binding var filePaths: [AnalysisFile]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analyse & Daten").font(.headline)
            VStack(spacing: 8) {
                ForEach($filePaths) { $file in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill").foregroundColor(.gray)
                        Text((file.filePath as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle).frame(width: 150, alignment: .leading)
                        TextField("Beschreibung...", text: $file.description).textFieldStyle(.roundedBorder)
                            .onChange(of: file.description) { _, newV in let f = applySmartFormatting(to: newV); if f != newV { file.description = f } }
                        Button("Öffnen") { NSWorkspace.shared.open(URL(fileURLWithPath: file.filePath)) }.buttonStyle(.bordered)
                        Button(action: { filePaths.removeAll { $0.id == file.id } }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain)
                    }.padding(8).background(Color(NSColor.textBackgroundColor).opacity(0.5)).cornerRadius(6)
                }
            }
            Button(action: addFiles) { HStack { Image(systemName: "plus"); Text("Dateien verknüpfen") }.font(.subheadline).foregroundColor(.blue) }.buttonStyle(.plain).padding(.top, 4)
        }
        .padding(12).background(Color(NSColor.textBackgroundColor).opacity(0.5)).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }

    func addFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { for url in panel.urls { if !filePaths.contains(where: { $0.filePath == url.path }) { filePaths.append(AnalysisFile(filePath: url.path)) } } }
    }
}
