import SwiftUI
import AppKit

@main
struct ChemJournalApp: App {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    /// Ein Datenbestand für alle Fenster.
    @State private var store = JournalStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 480, minHeight: 320)
                .preferredColorScheme(appTheme == .system ? nil : (appTheme == .light ? .light : .dark))
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Ausstehende (verzögerte) Speicherung nicht verlieren
                    store.saveBeforeTermination()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // iCloud: Änderungen eines anderen Macs sofort übernehmen
                    Task { await store.checkForExternalChanges() }
                }
        }
        .defaultSize(width: 1024, height: 653)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Widerrufen") { performUndo(redo: false) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Wiederholen") { performUndo(redo: true) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {
                Button("Neuer Ansatz") { NotificationCenter.default.post(name: .newExperiment, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Neues Projekt") { NotificationCenter.default.post(name: .newProject, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("Laborjournal speichern") { NotificationCenter.default.post(name: .saveJournal, object: nil) }
                    .keyboardShortcut("s", modifiers: .command)
                Divider()
                Button("Zeichnung aus ChemDraw importieren") {
                    NotificationCenter.default.post(name: .importFromChemDraw, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
                Divider()
                Button("Als PDF exportieren...") { NotificationCenter.default.post(name: .exportPDF, object: nil) }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Ansatz importieren (.chemjournal)...") { NotificationCenter.default.post(name: .importChemjournal, object: nil) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandMenu("Darstellung") {
                Picker("Erscheinungsbild", selection: $appTheme) {
                    Text("System").tag(AppTheme.system)
                    Text("Hell").tag(AppTheme.light)
                    Text("Dunkel").tag(AppTheme.dark)
                }
                Divider()
                Button("Auf optimale Breite einrasten") {
                    NotificationCenter.default.post(name: .snapToOptimalWidth, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .preferredColorScheme(appTheme == .system ? nil : (appTheme == .light ? .light : .dark))
        }
    }

    /// ⌘Z / ⇧⌘Z: Wird gerade in einem Textfeld getippt, wirkt es dort (wie in jeder Mac-App);
    /// sonst wird der letzte Schritt im Journal widerrufen – auch Löschen und Hinzufügen.
    private func performUndo(redo: Bool) {
        if let responder = NSApp.keyWindow?.firstResponder as? NSTextView,
           let manager = responder.undoManager, redo ? manager.canRedo : manager.canUndo {
            redo ? manager.redo() : manager.undo()
            return
        }
        // Gerade fokussiertes Feld beenden, damit es den widerrufenen Stand anzeigt
        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.keyWindow?.makeFirstResponder(nil) }
        if !(redo ? store.redo() : store.undo()) { NSSound.beep() }
    }
}
