import SwiftUI

struct ProjectDetailView: View {
    @Binding var project: Project
    var onAddExperiment: () -> Void
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "folder.fill").font(.system(size: 80)).foregroundColor(.blue.opacity(0.8))
            TextField("Projektname", text: $project.title).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center).textFieldStyle(.plain)
            Text("\(project.experiments.count) Ansätze in diesem Projekt").font(.title2).foregroundColor(.secondary)
            Button(action: onAddExperiment) { HStack { Image(systemName: "plus.circle.fill"); Text("Neuen Ansatz erstellen") }.font(.headline).foregroundColor(.white).padding().background(Color.blue).cornerRadius(10) }.buttonStyle(.plain)
            Spacer()
        }
        .padding(50).frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
        .onAppear {
            WindowSnapManager.shared.updateSnapWidth(1024)
        }
    }
}
