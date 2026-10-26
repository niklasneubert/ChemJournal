import AppKit

/// Sprache der Oberfläche: Deutsch (Standard) oder Englisch – unabhängig von der Systemsprache.
///
/// Die Wahl gilt ab dem nächsten Start. `activate()` muss vor dem ersten übersetzten Text laufen (`App.init`).
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case german = "de"
    case english = "en"

    var id: String { rawValue }
    static let defaultsKey = "appLanguage"

    /// Die Sprache dieses Programmlaufs.
    static let current: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .german

    /// Gespeicherte Wahl (kann von `current` abweichen, bis neu gestartet wurde).
    static var stored: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .german }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            // Menüs und Dialoge von macOS beim nächsten Start in derselben Sprache
            UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Name in der jeweiligen Sprache selbst (nicht übersetzt).
    var nativeName: String { self == .german ? "Deutsch" : "English" }

    /// Sprache + Region des Systems, z. B. „de_DE“ oder „en_DE“ – für Datumsangaben.
    var locale: Locale {
        Locale(identifier: rawValue + "_" + (Locale.current.region?.identifier ?? "DE"))
    }

    /// Legt die Sprache dieses Starts fest. macOS wählt die Sprache einer App beim Start anhand von „AppleLanguages“;
    /// ChemJournal speichert dort die eigene Wahl (Standard Deutsch). Hat macOS für diesen Start trotzdem eine andere
    /// Sprache gewählt (erster Start auf einem Mac mit anderer Systemsprache), startet ChemJournal einmal neu.
    static func activate() {
        guard !JournalStore.isRunningTests else { return }
        let args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        // Über Startparameter gesetzte Sprachen (z. B. für Tests) werden weder gespeichert noch korrigiert
        guard args[defaultsKey] == nil && args["AppleLanguages"] == nil else { return }
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let saved = UserDefaults.standard.persistentDomain(forName: bundleID)?["AppleLanguages"] as? [String]
        if saved != [current.rawValue] {
            UserDefaults.standard.set([current.rawValue], forKey: "AppleLanguages")
        }
        if Bundle.main.preferredLocalizations.first != current.rawValue && args["languageRelaunch"] == nil {
            // Noch nichts geladen oder angezeigt – einfach beenden und mit der richtigen Sprache neu starten
            startAfterExit(arguments: ["-languageRelaunch", "YES"])
            exit(0)
        }
    }

    /// Startet ChemJournal neu (nach dem Beenden – so wird vorher alles gespeichert).
    @MainActor
    static func relaunch() {
        startAfterExit(arguments: [])
        NSApp.terminate(nil)
    }

    /// Öffnet ChemJournal erneut, sobald dieser Prozess beendet ist.
    private static func startAfterExit(arguments: [String]) {
        let path = Bundle.main.bundleURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let pid = ProcessInfo.processInfo.processIdentifier
        let extra = arguments.isEmpty ? "" : " --args " + arguments.joined(separator: " ")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"\(path)\"\(extra)"]
        try? p.run()
    }
}

extension Date {
    /// Datum/Uhrzeit in der Sprache der App.
    nonisolated func appFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: AppLanguage.current.locale))
    }
}
