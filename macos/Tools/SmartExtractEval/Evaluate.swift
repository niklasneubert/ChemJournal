// Evaluate.swift – prüft Smart Extract gegen von Hand annotierte echte Synthesevorschriften.
//
// Wird von run.sh zusammen mit den Smart-Extract-Quellen der App kompiliert. Es testet also immer genau den
// Code, der in ChemJournal läuft. Aufruf siehe README.md.

import Foundation
import NaturalLanguage

// MARK: - Korpus-Format

struct SollZeile: Decodable {
    let namen: [String]
    let m: Double?       // Masse in g
    let n: Double?       // Stoffmenge in mol
    let V: Double?       // Volumen in ml
    let eq: Double?      // Äquivalente
    let optional: Bool?  // darf fehlen oder zusätzlich auftauchen (Quench-Reagenzien, Additive)
    var istOptional: Bool { optional ?? false }
}

struct Fall: Decodable {
    let id: String
    let quelle: String
    let text: String
    let soll: [SollZeile]
}

// MARK: - Vergleich

/// Namen vergleichen: Groß-/Kleinschreibung, Leerzeichen und Bindestriche egal; Teilstring zählt
/// ("monosubstituiertem BINOL 62b" passt zu "BINOL 62b").
func schluessel(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace && $0 != "-" } }

func namePasst(_ soll: SollZeile, _ ist: String) -> Bool {
    let i = schluessel(ist)
    guard !i.isEmpty else { return false }
    return soll.namen.contains { n in
        let s = schluessel(n)
        return s == i || (s.count >= 3 && i.contains(s)) || (i.count >= 3 && s.contains(i))
    }
}

/// Werte vergleichen (2 % Toleranz). Ein Wert, der nicht im Soll steht, darf auch nicht im Ist stehen.
func wertPasst(_ soll: Double?, _ ist: String) -> Bool {
    switch (soll, parseDecimal(ist)) {
    case (nil, nil): return true
    case let (s?, i?): return abs(s - i) <= max(1e-9, 0.02 * abs(s))
    default: return false
    }
}

func zeilePasst(_ s: SollZeile, _ r: ChemicalData) -> Bool {
    wertPasst(s.m, r.mass) && wertPasst(s.n, r.amount) && wertPasst(s.V, r.volume) && wertPasst(s.eq, r.equivalents)
}

func beschreibung(_ s: SollZeile) -> String {
    func f(_ v: Double?) -> String { v.map { "\($0)" } ?? "–" }
    return "m=\(f(s.m)) n=\(f(s.n)) V=\(f(s.V)) eq=\(f(s.eq))"
}

func beschreibung(_ r: ChemicalData) -> String {
    func f(_ v: String) -> String { v.isEmpty ? "–" : v }
    return "m=\(f(r.mass)) n=\(f(r.amount)) V=\(f(r.volume)) eq=\(f(r.equivalents))"
}

// MARK: - Auswertung

struct Bilanz {
    var pflicht = 0, nameGefunden = 0, richtig = 0, zuViel = 0, nurName = 0, faelleOK = 0, faelle = 0
    mutating func add(_ o: Bilanz) {
        pflicht += o.pflicht; nameGefunden += o.nameGefunden; richtig += o.richtig
        zuViel += o.zuViel; nurName += o.nurName; faelleOK += o.faelleOK; faelle += o.faelle
    }
    var quote: Double { pflicht == 0 ? 100 : 100 * Double(richtig) / Double(pflicht) }
    func zusammenfassung() -> String {
        String(format: "%d/%d Fälle fehlerfrei | %d Pflichtzeilen | Name gefunden %.1f %% | komplett richtig %.1f %% | falsche Zusatzzeilen %d | Zeilen nur mit Name %d",
               faelleOK, faelle, pflicht, pflicht == 0 ? 100 : 100 * Double(nameGefunden) / Double(pflicht), quote, zuViel, nurName)
    }
}

func bewerte(_ fall: Fall, model: NLModel?, ausfuehrlich: Bool) -> Bilanz {
    let zeilen = SmartExtractor(model: model).extract(from: fall.text)
    var belegt = Set<Int>()
    var meldungen: [String] = []
    var b = Bilanz(faelle: 1)

    // Pflichtzeilen zuerst zuordnen, damit optionale Zeilen ihnen nichts wegnehmen
    for s in fall.soll.filter({ !$0.istOptional }) + fall.soll.filter(\.istOptional) {
        let kandidaten = zeilen.indices.filter { !belegt.contains($0) && namePasst(s, zeilen[$0].name) }
        let wahl = kandidaten.first { zeilePasst(s, zeilen[$0]) } ?? kandidaten.first
        if !s.istOptional { b.pflicht += 1 }
        guard let i = wahl else {
            if !s.istOptional { meldungen.append("   ✗ fehlt: \(s.namen[0])  (soll \(beschreibung(s)))") }
            continue
        }
        belegt.insert(i)
        let ok = zeilePasst(s, zeilen[i])
        if !s.istOptional {
            b.nameGefunden += 1
            if ok { b.richtig += 1 }
        }
        if !ok && !s.istOptional {
            meldungen.append("   ≠ \(s.namen[0]): soll \(beschreibung(s)) | ist \(beschreibung(zeilen[i]))")
        }
    }
    for (i, r) in zeilen.enumerated() where !belegt.contains(i) {
        if r.hasAnyQuantity {
            b.zuViel += 1
            meldungen.append("   + zu viel: \"\(r.name)\" \(beschreibung(r))")
        } else {
            b.nurName += 1
            if ausfuehrlich { meldungen.append("   · nur Name: \"\(r.name)\"") }
        }
    }
    let fehlerfrei = b.richtig == b.pflicht && b.zuViel == 0
    if fehlerfrei { b.faelleOK = 1 }
    if !fehlerfrei || ausfuehrlich {
        print("\(fehlerfrei ? "✔" : "✘") \(fall.id)  [\(fall.quelle)]  \(b.richtig)/\(b.pflicht)")
        meldungen.forEach { print($0) }
        if ausfuehrlich {
            print("   Ist-Tabelle:")
            for r in zeilen { print("     \(r.name.isEmpty ? "(ohne Name)" : r.name)  \(beschreibung(r))") }
        }
    }
    return b
}

// MARK: - Einstieg

@main
struct SmartExtractEval {
    static func main() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        func option(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
        }
        func flag(_ name: String) -> Bool {
            guard let i = args.firstIndex(of: name) else { return false }
            args.remove(at: i); return true
        }
        let modellPfad = option("--model")
        let mindestquote = option("--min").flatMap(Double.init)
        let nur = option("--case")
        let ausfuehrlich = flag("-v")
        let dateien = args

        let model = try modellPfad.map { try NLModel(contentsOf: URL(fileURLWithPath: $0)) }
        print(model == nil ? "Modus: nur Regeln (ohne Modell)" : "Modus: mit Modell \(URL(fileURLWithPath: modellPfad!).deletingPathExtension().lastPathComponent)")

        var gesamt = Bilanz()
        for datei in dateien {
            let faelle = try JSONDecoder().decode([Fall].self, from: Data(contentsOf: URL(fileURLWithPath: datei)))
                .filter { nur == nil || $0.id == nur }
            guard !faelle.isEmpty else { continue }
            var b = Bilanz()
            print("\n== \(URL(fileURLWithPath: datei).lastPathComponent)")
            for fall in faelle {
                b.add(bewerte(fall, model: model, ausfuehrlich: ausfuehrlich || nur != nil))
            }
            print(b.zusammenfassung())
            gesamt.add(b)
        }
        if gesamt.faelle == 0 { print("Kein passender Fall gefunden."); exit(1) }
        if dateien.count > 1 && nur == nil { print("\nGesamt: " + gesamt.zusammenfassung()) }
        if let mindest = mindestquote, gesamt.quote < mindest {
            print(String(format: "\nUNTER DER MINDESTQUOTE: %.1f %% < %.1f %%", gesamt.quote, mindest))
            exit(1)
        }
    }
}
