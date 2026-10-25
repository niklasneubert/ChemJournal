import SwiftUI

/// Zustand der PubChem-Suche für ein CAS-Feld.
enum CASLookupStatus: Equatable {
    case idle
    case loading
    case found(String)
    case saved(String)
    case failed(String)
}

/// Kleines Symbol rechts im CAS-Feld: lädt / gefunden (Tooltip mit PubChem-Namen) / Fehler (Tooltip mit Grund).
struct CASStatusIcon: View {
    let status: CASLookupStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView().controlSize(.mini)
                    .help("Suche Molmasse und Dichte in PubChem …")
            case .found(let title):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .help("Aus PubChem übernommen: \(title)")
            case .saved(let info):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                    .help(info)
            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(reason)
            }
        }
        .font(.system(size: 11))
        .padding(.trailing, 5)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch status {
        case .idle: ""
        case .loading: "PubChem-Suche läuft"
        case .found(let title): "Aus PubChem übernommen: \(title)"
        case .saved(let info): info
        case .failed(let reason): reason
        }
    }
}

/// Gemeinsame Logik für Chemikalien- und Produktzeile beim Eintippen einer CAS-Nummer.
///
/// 1. CAS ist in der lokalen CAS-Datenbank → Werte sofort eintragen (offline).
/// 2. Sonst PubChem fragen → nur leere Felder füllen (eigene Werte bleiben) → Ergebnis speichern.
@MainActor
enum CASAutofill {
    struct RowValues { var name: String; var molarMass: String; var density: String }

    static func casChanged(_ rawCAS: String,
                           current: @escaping () -> (cas: String, values: RowValues),
                           status: Binding<CASLookupStatus>,
                           apply: @escaping (_ molarMass: String?, _ density: String?) -> Void) {
        guard let cas = CASNumber.normalized(rawCAS) else {
            status.wrappedValue = .idle
            return
        }
        let db = CASDatabase.shared
        if let saved = db.entry(for: cas), !(saved.molarMass.isEmpty && saved.density.isEmpty) {
            apply(saved.molarMass.isEmpty ? nil : saved.molarMass, saved.density.isEmpty ? nil : saved.density)
            status.wrappedValue = .saved(savedInfo(saved))
            // Fehlender Wert (z. B. Dichte) einmalig in PubChem nachschlagen
            if (saved.molarMass.isEmpty || saved.density.isEmpty) && !saved.pubChemChecked {
                lookup(cas, current: current, status: status, apply: apply)
            }
            return
        }
        lookup(cas, current: current, status: status, apply: apply)
    }

    /// Speichert die Werte der Zeile als eigene Eingabe (beim Verlassen des M- oder d-Feldes).
    static func saveUserValues(cas: String, values: RowValues) {
        CASDatabase.shared.recordUserValues(cas: cas, name: values.name, molarMass: values.molarMass, density: values.density)
    }

    private static func lookup(_ cas: String,
                               current: @escaping () -> (cas: String, values: RowValues),
                               status: Binding<CASLookupStatus>,
                               apply: @escaping (_ molarMass: String?, _ density: String?) -> Void) {
        status.wrappedValue = .loading
        Task {
            do {
                let result = try await CASLookupService.shared.lookup(cas)
                guard CASNumber.normalized(current().cas) == cas else { return }   // inzwischen andere CAS
                let before = current().values
                let m = format3(result.molarMass), d = result.density.map(format4)
                apply(before.molarMass.isEmpty ? m : nil, before.density.isEmpty ? d : nil)
                CASDatabase.shared.recordPubChem(cas: cas, result: result)
                // Hatte die Zeile schon eigene Werte, gehören sie zu dieser CAS-Nummer
                if !before.molarMass.isEmpty || !before.density.isEmpty {
                    saveUserValues(cas: cas, values: current().values)
                }
                let kept = (!before.molarMass.isEmpty || (!before.density.isEmpty && d != nil)) ? " – eigene Werte beibehalten" : ""
                status.wrappedValue = .found(result.title + (result.density == nil ? " (keine Dichte in PubChem)" : "") + kept)
            } catch {
                guard CASNumber.normalized(current().cas) == cas else { return }
                if case CASLookupService.LookupError.notFound = error { CASDatabase.shared.markPubChemChecked(cas: cas) }
                // Offline oder unbekannt: vorhandene eigene Werte trotzdem für diese CAS merken
                let values = current().values
                if !values.molarMass.isEmpty || !values.density.isEmpty { saveUserValues(cas: cas, values: values) }
                status.wrappedValue = .failed(error.localizedDescription + " Eigene Werte werden für diese CAS-Nummer gespeichert.")
            }
        }
    }

    private static func savedInfo(_ e: CASEntry) -> String {
        let date = e.updatedAt.formatted(date: .abbreviated, time: .omitted)
        let name = e.name.isEmpty ? "" : "\(e.name) – "
        return "\(name)lokal gespeichert (\(e.source.rawValue), \(date))"
    }
}
