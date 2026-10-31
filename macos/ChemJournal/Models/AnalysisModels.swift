import Foundation

// Aufreinigung & Analytik einer Stufe: beliebig viele Einträge, jeder mit einer Methode (NMR, IR, Säule, …), eigenen
// Feldern und verknüpften Dateien. Die Felder stehen als Text in `values` (Schlüssel siehe `AnalysisMethod.fields`),
// so bleibt das Dateiformat stabil, wenn Felder dazukommen.

nonisolated enum AnalysisGroup: String, CaseIterable, Sendable {
    // Reihenfolge wie im Labor: erst aufreinigen, dann analysieren
    case purification, spectroscopy, other

    var title: String {
        switch self {
        case .spectroscopy: String(localized: "Analytik")
        case .purification: String(localized: "Chromatographie & Aufreinigung")
        case .other: String(localized: "Weitere")
        }
    }

    var methods: [AnalysisMethod] { AnalysisMethod.allCases.filter { $0.group == self } }
}

/// Ein Eingabefeld eines Analyse-Formulars.
nonisolated struct AnalysisField: Identifiable, Sendable {
    enum Kind: Sendable {
        case text
        /// Zahl (als Text gespeichert) mit Einheit hinter dem Feld.
        case number(unit: String)
        /// Freitext mit Vorschlägen (z. B. Lösungsmittel); eigene Eingaben sind erlaubt.
        case choice([String])
        /// Wie `choice`, aber mehrere Vorschläge gleichzeitig ("¹H, ¹³C{¹H}"), durch Komma getrennt gespeichert.
        case multiChoice([String])
        /// Mehrzeiliger Text (Signale, Bemerkungen).
        case multiline
    }

    let key: String
    let label: String
    let kind: Kind
    var id: String { key }

    var unit: String? { if case .number(let u) = kind, !u.isEmpty { return u } else { return nil } }
    var isMultiline: Bool { if case .multiline = kind { return true } else { return false } }
}

nonisolated enum AnalysisMethod: String, CaseIterable, Sendable {
    case nmr, ir, uvVis, ms, epr, xrd, column, tlc, gc, recrystallization, distillation, meltingPoint, opticalRotation, other

    var group: AnalysisGroup {
        switch self {
        case .nmr, .ir, .uvVis, .ms, .epr, .xrd: .spectroscopy
        case .column, .tlc, .gc, .recrystallization, .distillation: .purification
        case .meltingPoint, .opticalRotation, .other: .other
        }
    }

    var title: String {
        switch self {
        case .nmr: String(localized: "NMR-Spektroskopie")
        case .ir: String(localized: "IR-Spektroskopie")
        case .uvVis: String(localized: "UV/Vis-Spektroskopie")
        case .ms: String(localized: "Massenspektrometrie")
        case .epr: String(localized: "EPR-Spektroskopie")
        case .xrd: String(localized: "Röntgenbeugung (XRD)")
        case .column: String(localized: "Säulenchromatographie (LC)")
        case .tlc: String(localized: "Dünnschichtchromatographie (DC)")
        case .gc: String(localized: "Gaschromatographie (GC)")
        case .recrystallization: String(localized: "Umkristallisation")
        case .distillation: String(localized: "Destillation")
        case .meltingPoint: String(localized: "Schmelzpunkt")
        case .opticalRotation: String(localized: "Drehwert")
        case .other: String(localized: "Sonstiges")
        }
    }

    /// Kurzer Name für Überschriften und PDF ("Säule" statt "Säulenchromatographie").
    var shortTitle: String {
        switch self {
        case .nmr: "NMR"
        case .ir: "IR"
        case .uvVis: "UV/Vis"
        case .ms: "MS"
        case .epr: "EPR"
        case .xrd: "XRD"
        case .column: String(localized: "Säulenchromatographie (LC)")
        case .tlc: String(localized: "DC")
        case .gc: "GC"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .nmr: "waveform.path.ecg"
        case .ir: "waveform"
        case .uvVis: "rainbow"
        case .ms: "chart.bar.xaxis"
        case .epr: "dot.radiowaves.left.and.right"
        case .xrd: "circle.hexagongrid"
        case .column: "line.3.horizontal.decrease"
        case .tlc: "rectangle.split.1x2"
        case .gc: "chart.xyaxis.line"
        case .recrystallization: "snowflake"
        case .distillation: "flame"
        case .meltingPoint: "thermometer.medium"
        case .opticalRotation: "dial.medium"
        case .other: "doc.text"
        }
    }

    // MARK: Felder

    static let nmrSolvents = ["CDCl₃", "DMSO-d₆", "CD₃OD", "C₆D₆", "CD₂Cl₂", "Aceton-d₆", "CD₃CN", "D₂O", "THF-d₈", "Toluol-d₈"]
    static let nmrExperiments = ["¹H", "¹³C{¹H}", "¹⁹F", "³¹P{¹H}", "¹¹B", "²⁹Si", "DEPT-135", "COSY", "HSQC", "HMBC", "NOESY"]
    static let twoDimensional: Set<String> = ["DEPT-135", "COSY", "HSQC", "HMBC", "NOESY"]
    static let solvents = ["MeCN", "MeOH", "EtOH", "CH₂Cl₂", "CHCl₃", "THF", "Toluol", "DMSO", "H₂O", "Cyclohexan", "n-Hexan"]

    var fields: [AnalysisField] {
        let notes = AnalysisField(key: "notes", label: String(localized: "Bemerkungen"), kind: .multiline)
        switch self {
        case .nmr:
            return [
                // Mehrere Kerne, wenn eine verknüpfte Datei mehrere Spektren enthält
                AnalysisField(key: "nucleus", label: String(localized: "Kerne / Experimente"),
                              kind: .multiChoice(Self.nmrExperiments)),
                AnalysisField(key: "frequency", label: String(localized: "Frequenz"), kind: .number(unit: "MHz")),
                AnalysisField(key: "solvent", label: String(localized: "Lösungsmittel"), kind: .choice(Self.nmrSolvents)),
                AnalysisField(key: "sampleMass", label: String(localized: "Probenmasse"), kind: .number(unit: "mg")),
                AnalysisField(key: "temperature", label: String(localized: "Temperatur"), kind: .number(unit: "°C")),
                AnalysisField(key: "data", label: String(localized: "Signale (δ in ppm)"), kind: .multiline),
                AnalysisField(key: "notes", label: String(localized: "Anmerkungen"), kind: .multiline),
            ]
        case .ir:
            return [
                AnalysisField(key: "technique", label: String(localized: "Messmethode"),
                              kind: .choice(["ATR", String(localized: "KBr-Pressling"), "Film", String(localized: "Lösung"), "Nujol"])),
                AnalysisField(key: "data", label: String(localized: "Banden ṽ (cm⁻¹)"), kind: .multiline),
            ]
        case .uvVis:
            return [
                AnalysisField(key: "solvent", label: String(localized: "Lösungsmittel"), kind: .choice(Self.solvents)),
                AnalysisField(key: "concentration", label: String(localized: "Konzentration c"), kind: .number(unit: "mol/L")),
                AnalysisField(key: "pathLength", label: String(localized: "Schichtdicke d"), kind: .number(unit: "cm")),
                AnalysisField(key: "lambdaMax", label: "λmax", kind: .number(unit: "nm")),
                AnalysisField(key: "absorbance", label: String(localized: "Absorbanz A bei λmax"), kind: .number(unit: "")),
                AnalysisField(key: "data", label: String(localized: "Weitere Banden"), kind: .multiline),
            ]
        case .ms:
            return [
                AnalysisField(key: "kind", label: String(localized: "Art"), kind: .choice(["HRMS", "LRMS"])),
                AnalysisField(key: "ionization", label: String(localized: "Ionisierung"),
                              kind: .choice(["ESI", "APCI", "EI", "CI", "MALDI", "APPI", "FD", "GC-MS (EI)", "LC-MS (ESI)"])),
                AnalysisField(key: "polarity", label: String(localized: "Modus"),
                              kind: .choice([String(localized: "positiv"), String(localized: "negativ")])),
                AnalysisField(key: "formula", label: String(localized: "Summenformel"), kind: .text),
                AnalysisField(key: "ion", label: "Ion",
                              kind: .choice(["[M+H]⁺", "[M+Na]⁺", "[M+K]⁺", "[M+NH₄]⁺", "[M]⁺", "[M]⁺•", "[M−H]⁻", "[M+Cl]⁻", "[M+HCOO]⁻"])),
                AnalysisField(key: "mzCalc", label: String(localized: "m/z berechnet"), kind: .number(unit: "")),
                AnalysisField(key: "mzFound", label: String(localized: "m/z gefunden"), kind: .number(unit: "")),
                AnalysisField(key: "data", label: String(localized: "Weitere Signale"), kind: .multiline),
            ]
        case .epr:
            // Angaben wie in Experimentalteilen üblich (CW-EPR: Frequenz, Leistung, Modulation, Temperatur, Probe;
            // Ergebnisse: g-Faktoren und Hyperfeinkopplungen A in MHz mit Kern, IUPAC)
            return [
                AnalysisField(key: "technique", label: String(localized: "Methode"),
                              kind: .choice(["CW-EPR", String(localized: "Puls-EPR (ESE)"), "ENDOR", "HYSCORE", "ESEEM", "DEER/PELDOR",
                                             String(localized: "Spin-Trapping")])),
                AnalysisField(key: "band", label: String(localized: "Frequenzband"),
                              kind: .choice(["X-Band (~9.5 GHz)", "Q-Band (~34 GHz)", "W-Band (~94 GHz)", "S-Band (~3 GHz)", "L-Band (~1 GHz)"])),
                AnalysisField(key: "frequency", label: String(localized: "Mikrowellenfrequenz"), kind: .number(unit: "GHz")),
                AnalysisField(key: "power", label: String(localized: "Mikrowellenleistung"), kind: .number(unit: "mW")),
                AnalysisField(key: "modAmp", label: String(localized: "Modulationsamplitude"), kind: .number(unit: "mT")),
                AnalysisField(key: "modFreq", label: String(localized: "Modulationsfrequenz"), kind: .number(unit: "kHz")),
                AnalysisField(key: "temperature", label: String(localized: "Temperatur"), kind: .number(unit: "K")),
                AnalysisField(key: "sampleState", label: String(localized: "Probenzustand"),
                              kind: .choice([String(localized: "Lösung"), String(localized: "gefrorene Lösung"),
                                             String(localized: "Feststoff/Pulver"), String(localized: "Einkristall")])),
                AnalysisField(key: "solvent", label: String(localized: "Lösungsmittel / Matrix"), kind: .choice(Self.solvents)),
                AnalysisField(key: "concentration", label: String(localized: "Konzentration"), kind: .number(unit: "mM")),
                AnalysisField(key: "field", label: String(localized: "Feldbereich (Mitte / Sweep)"), kind: .text),
                AnalysisField(key: "scans", label: String(localized: "Scans"), kind: .number(unit: "")),
                AnalysisField(key: "gValues", label: String(localized: "g-Faktoren"), kind: .text),
                AnalysisField(key: "hyperfine", label: String(localized: "Hyperfeinkopplung A (MHz, mit Kern)"), kind: .text),
                AnalysisField(key: "zfs", label: String(localized: "Nullfeldaufspaltung D, E"), kind: .text),
                AnalysisField(key: "simulation", label: String(localized: "Simulation"),
                              kind: .choice(["EasySpin", "SimFonia", "Bruker Xenon"])),
                AnalysisField(key: "data", label: String(localized: "Weitere Ergebnisse"), kind: .multiline),
                AnalysisField(key: "notes", label: String(localized: "Anmerkungen"), kind: .multiline),
            ]
        case .xrd:
            return [
                AnalysisField(key: "kind", label: String(localized: "Art"),
                              kind: .choice([String(localized: "Einkristall (SC-XRD)"), String(localized: "Pulver (PXRD)")])),
                AnalysisField(key: "radiation", label: String(localized: "Strahlung"),
                              kind: .choice(["Mo Kα (0.71073 Å)", "Cu Kα (1.54184 Å)", "Ga Kα (1.34139 Å)", "Ag Kα (0.56087 Å)", "Synchrotron"])),
                AnalysisField(key: "temperature", label: String(localized: "Temperatur"), kind: .number(unit: "K")),
                AnalysisField(key: "crystalSystem", label: String(localized: "Kristallsystem"),
                              kind: .choice([String(localized: "triklin"), String(localized: "monoklin"), String(localized: "orthorhombisch"),
                                             String(localized: "tetragonal"), String(localized: "trigonal"), String(localized: "hexagonal"),
                                             String(localized: "kubisch")])),
                AnalysisField(key: "spaceGroup", label: String(localized: "Raumgruppe"), kind: .text),
                AnalysisField(key: "cell", label: String(localized: "Zellparameter"), kind: .text),
                AnalysisField(key: "rFactors", label: "R1 / wR2", kind: .text),
                AnalysisField(key: "ccdc", label: String(localized: "CCDC-Nummer"), kind: .text),
                AnalysisField(key: "twoTheta", label: String(localized: "2θ-Bereich"), kind: .text),
                AnalysisField(key: "crystal", label: String(localized: "Kristall"), kind: .text),
                notes,
            ]
        case .column:
            return [
                AnalysisField(key: "stationaryPhase", label: String(localized: "Stationäre Phase"),
                              kind: .choice([String(localized: "Kieselgel 60 (40–63 µm)"), String(localized: "Kieselgel 60 (63–200 µm)"),
                                             String(localized: "Al₂O₃ neutral"), String(localized: "Al₂O₃ basisch"), String(localized: "Al₂O₃ sauer"),
                                             "C18 (Reversed Phase)", "Florisil"])),
                AnalysisField(key: "eluent", label: String(localized: "Eluent"), kind: .text),
                AnalysisField(key: "diameter", label: String(localized: "Säulendurchmesser"), kind: .number(unit: "cm")),
                AnalysisField(key: "height", label: String(localized: "Füllhöhe"), kind: .number(unit: "cm")),
                AnalysisField(key: "crudeMass", label: String(localized: "Rohprodukt"), kind: .number(unit: "mg")),
                AnalysisField(key: "isolatedMass", label: String(localized: "Isoliert"), kind: .number(unit: "mg")),
                AnalysisField(key: "rf", label: String(localized: "Rf (Produkt)"), kind: .text),
                AnalysisField(key: "fractions", label: String(localized: "Produktfraktionen"), kind: .text),
                notes,
            ]
        case .tlc:
            return [
                AnalysisField(key: "eluent", label: String(localized: "Eluent"), kind: .text),
                AnalysisField(key: "detection", label: String(localized: "Detektion"),
                              kind: .choice(["UV 254 nm", "UV 365 nm", "KMnO₄", "Vanillin", String(localized: "Anisaldehyd"), "CAM",
                                             "Ninhydrin", String(localized: "Iod"), String(localized: "Bromkresolgrün")])),
                AnalysisField(key: "rf", label: String(localized: "Rf-Werte"), kind: .text),
                notes,
            ]
        case .gc:
            return [
                AnalysisField(key: "column", label: String(localized: "Säule"), kind: .text),
                AnalysisField(key: "program", label: String(localized: "Temperaturprogramm"), kind: .text),
                AnalysisField(key: "carrier", label: String(localized: "Trägergas / Fluss"), kind: .text),
                AnalysisField(key: "detector", label: String(localized: "Detektor"), kind: .choice(["FID", "MS", String(localized: "WLD (TCD)"), "ECD"])),
                AnalysisField(key: "retention", label: String(localized: "Retentionszeit(en)"), kind: .text),
                AnalysisField(key: "purity", label: String(localized: "Reinheit / Umsatz"), kind: .number(unit: "%")),
                notes,
            ]
        case .recrystallization:
            return [
                AnalysisField(key: "solvent", label: String(localized: "Lösungsmittel"), kind: .choice(Self.solvents)),
                AnalysisField(key: "volume", label: String(localized: "Volumen"), kind: .number(unit: "mL")),
                AnalysisField(key: "crudeMass", label: String(localized: "Rohprodukt"), kind: .number(unit: "mg")),
                AnalysisField(key: "crystalMass", label: String(localized: "Kristalle"), kind: .number(unit: "mg")),
                AnalysisField(key: "conditions", label: String(localized: "Bedingungen"), kind: .text),
                AnalysisField(key: "appearance", label: String(localized: "Aussehen"), kind: .text),
                AnalysisField(key: "meltingPoint", label: String(localized: "Smp."), kind: .number(unit: "°C")),
                notes,
            ]
        case .distillation:
            return [
                AnalysisField(key: "technique", label: String(localized: "Art"),
                              kind: .choice([String(localized: "einfach"), String(localized: "fraktioniert"), String(localized: "Vakuum"),
                                             String(localized: "Kugelrohr"), String(localized: "Wasserdampf")])),
                AnalysisField(key: "pressure", label: String(localized: "Druck"), kind: .number(unit: "mbar")),
                AnalysisField(key: "boilingPoint", label: String(localized: "Siedepunkt (Kopf)"), kind: .number(unit: "°C")),
                AnalysisField(key: "bathTemp", label: String(localized: "Badtemperatur"), kind: .number(unit: "°C")),
                AnalysisField(key: "crudeMass", label: String(localized: "Einsatz"), kind: .number(unit: "mg")),
                AnalysisField(key: "distillateMass", label: String(localized: "Destillat"), kind: .number(unit: "mg")),
                notes,
            ]
        case .meltingPoint:
            return [
                AnalysisField(key: "found", label: String(localized: "Smp. gefunden"), kind: .number(unit: "°C")),
                AnalysisField(key: "literature", label: String(localized: "Smp. Literatur"), kind: .number(unit: "°C")),
                AnalysisField(key: "method", label: String(localized: "Methode"),
                              kind: .choice([String(localized: "Kapillare"), String(localized: "Kofler-Heizbank"), "DSC"])),
                notes,
            ]
        case .opticalRotation:
            // Angabe wie in der Literatur: [α]D²⁰ = +25.3 (c 1.00, CHCl₃); c in g/100 mL, l in dm
            return [
                AnalysisField(key: "measured", label: String(localized: "Gemessener Drehwinkel α"), kind: .number(unit: "°")),
                AnalysisField(key: "specific", label: String(localized: "Spezifischer Drehwert [α] (falls abgelesen)"), kind: .text),
                AnalysisField(key: "wavelength", label: String(localized: "Wellenlänge"),
                              kind: .choice(["589 nm (Na-D)", "578 nm (Hg)", "546 nm (Hg)", "436 nm (Hg)", "405 nm (Hg)", "365 nm (Hg)"])),
                AnalysisField(key: "temperature", label: String(localized: "Temperatur"), kind: .number(unit: "°C")),
                AnalysisField(key: "solvent", label: String(localized: "Lösungsmittel"), kind: .choice(Self.solvents)),
                AnalysisField(key: "concentration", label: String(localized: "Konzentration c"), kind: .number(unit: "g/100 mL")),
                AnalysisField(key: "pathLength", label: String(localized: "Küvettenlänge l"), kind: .number(unit: "dm")),
                AnalysisField(key: "literature", label: String(localized: "Literaturwert [α]"), kind: .text),
                notes,
            ]
        case .other:
            return [
                AnalysisField(key: "title", label: String(localized: "Bezeichnung"), kind: .text),
                AnalysisField(key: "notes", label: String(localized: "Ergebnis / Beschreibung"), kind: .multiline),
            ]
        }
    }

    /// Felder, die ein neuer Eintrag derselben Methode in der Stufe übernimmt (gleiches Lösungsmittel, gleicher Eluent …).
    var inheritedKeys: [String] {
        switch self {
        case .nmr: ["solvent", "sampleMass", "temperature"]
        case .ir: ["technique"]
        case .uvVis: ["solvent", "concentration", "pathLength"]
        case .ms: ["kind", "ionization", "polarity", "formula"]
        case .epr: ["technique", "band", "frequency", "power", "modAmp", "modFreq", "temperature", "sampleState", "solvent"]
        case .xrd: ["kind", "radiation", "temperature"]
        case .column: ["stationaryPhase", "eluent"]
        case .tlc: ["eluent", "detection"]
        case .gc: ["column", "program", "carrier", "detector"]
        case .recrystallization: ["solvent"]
        case .distillation: ["technique"]
        case .meltingPoint: ["method"]
        case .opticalRotation: ["wavelength", "temperature", "solvent", "pathLength"]
        case .other: []
        }
    }
}

nonisolated extension AnalysisMethod: Codable {
    /// Unbekannte Methoden (aus einer neueren Version) werden zu „Sonstiges“, statt die Datei unlesbar zu machen.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AnalysisMethod(rawValue: raw) ?? .other
    }
}

/// Ein berechneter Wert im Formular ("Δ = −0.9 ppm", "Wiederfindung 72 %").
nonisolated struct AnalysisResult: Hashable, Sendable {
    let label: String
    let value: String
}

/// Ein Eintrag unter „Aufreinigung & Analytik“: eine Messung oder ein Aufreinigungsschritt.
nonisolated struct AnalysisEntry: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var method: AnalysisMethod
    /// Welche Probe ("Produkt 3", "Rohprodukt").
    var sample: String = ""
    var values: [String: String] = [:]
    var files: [AnalysisFile] = []
    var isExpanded = true
    var createdAt = Date()

    init(method: AnalysisMethod, sample: String = "", values: [String: String] = [:], files: [AnalysisFile] = []) {
        self.method = method; self.sample = sample; self.values = values; self.files = files
    }

    private enum CodingKeys: String, CodingKey { case id, method, sample, values, files, isExpanded, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        method = try c.decodeIfPresent(AnalysisMethod.self, forKey: .method) ?? .other
        sample = try c.decodeIfPresent(String.self, forKey: .sample) ?? ""
        values = try c.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
        files = try c.decodeIfPresent([AnalysisFile].self, forKey: .files) ?? []
        isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func value(_ key: String) -> String { (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Mehrfachauswahl aus einem Feld: "¹H, ¹³C{¹H}" → ["¹H", "¹³C{¹H}"].
    static func list(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Überschrift: "¹H-NMR", "HRMS", "Säulenchromatographie", bei „Sonstiges“ die eigene Bezeichnung.
    var heading: String {
        switch method {
        case .nmr:
            // "¹H, ¹³C{¹H}, COSY" → "¹H/¹³C{¹H}-NMR, COSY"
            let nuclei = Self.list(value("nucleus"))
            guard !nuclei.isEmpty else { return "NMR" }
            let oneD = nuclei.filter { !AnalysisMethod.twoDimensional.contains($0) }
            let twoD = nuclei.filter { AnalysisMethod.twoDimensional.contains($0) }
            return ((oneD.isEmpty ? [] : [oneD.joined(separator: "/") + "-NMR"]) + twoD).joined(separator: ", ")
        case .epr:
            // "CW-EPR", "Puls-EPR", "ENDOR" … oder schlicht "EPR"
            let technique = value("technique")
            if technique.isEmpty { return "EPR" }
            return technique.hasPrefix(String(localized: "Puls-EPR")) ? String(localized: "Puls-EPR") : technique
        case .xrd:
            let kind = value("kind").lowercased()
            return kind.contains("pxrd") || kind.contains("pulver") || kind.contains("powder") ? "PXRD"
                : (kind.contains("sc-xrd") || kind.contains("einkristall") || kind.contains("single") ? "SC-XRD" : "XRD")
        case .ms:
            let kind = value("kind")
            return kind.isEmpty ? "MS" : kind
        case .ir, .uvVis:
            return method.shortTitle
        case .other:
            let title = value("title")
            return title.isEmpty ? method.title : title
        default:
            return method.title
        }
    }

    // MARK: Berechnungen

    /// Berechnete Werte, sobald die nötigen Felder ausgefüllt sind.
    var results: [AnalysisResult] {
        switch method {
        case .ms:
            guard let calc = number("mzCalc"), let found = number("mzFound"), calc > 0 else { return [] }
            let ppm = (found - calc) / calc * 1e6
            return [AnalysisResult(label: String(localized: "Massenabweichung"), value: "Δ = \(Self.signed(ppm, digits: 1)) ppm")]
        case .uvVis:
            guard let a = number("absorbance"), let c = number("concentration"), c > 0 else { return [] }
            let d = number("pathLength") ?? 1
            guard d > 0 else { return [] }
            return [AnalysisResult(label: String(localized: "Extinktionskoeffizient"),
                                   value: "ε = \(Self.grouped(a / (c * d))) L·mol⁻¹·cm⁻¹")]
        case .column:
            return recovery(from: "crudeMass", to: "isolatedMass")
        case .recrystallization:
            return recovery(from: "crudeMass", to: "crystalMass")
        case .distillation:
            return recovery(from: "crudeMass", to: "distillateMass")
        case .opticalRotation:
            var r: [AnalysisResult] = []
            if value("specific").isEmpty, let computed = computedSpecificRotation {
                r.append(AnalysisResult(label: String(localized: "Spezifischer Drehwert"), value: "[α] = \(Self.rotation(computed))"))
            }
            if let specific = specificRotation, let lit = Self.signedNumber(value("literature")), lit != 0 {
                r.append(AnalysisResult(label: String(localized: "Optische Reinheit"), value: String(format: "%.0f %%", specific / lit * 100)))
            }
            return r
        default:
            return []
        }
    }

    // MARK: Drehwert

    /// [α] = 100 · α / (l · c) mit c in g/100 mL und l in dm (ohne Angabe 1 dm).
    private var computedSpecificRotation: Double? {
        guard let alpha = Self.signedNumber(value("measured")), let c = number("concentration"), c > 0 else { return nil }
        let l = number("pathLength") ?? 1
        guard l > 0 else { return nil }
        return 100 * alpha / (l * c)
    }

    /// Abgelesener Wert, sonst der berechnete.
    private var specificRotation: Double? { Self.signedNumber(value("specific")) ?? computedSpecificRotation }

    /// Zahl mit Vorzeichen, auch "+25.3", "−12,4°".
    static func signedNumber(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "°", with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }

    /// "+25.3", "−4.12": immer mit Vorzeichen, bei kleinen Werten zwei Nachkommastellen.
    static func rotation(_ v: Double) -> String { signed(v, digits: abs(v) < 10 ? 2 : 1) }

    /// "[α]D²⁰" – D für die Natrium-D-Linie, sonst die Wellenlänge tiefgestellt; die Temperatur hochgestellt.
    var rotationSymbol: String {
        let sub: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻", ".": "·"]
        let wl = value("wavelength")
        let nm = String(wl.prefix { $0.isNumber })
        let lambda = wl.isEmpty || nm == "589" || wl.contains("D") ? "D" : String(nm.compactMap { sub[$0] })
        let temp = String(value("temperature").compactMap { sup[$0] })
        return "[α]" + lambda + temp
    }

    private func recovery(from crudeKey: String, to productKey: String) -> [AnalysisResult] {
        guard let crude = number(crudeKey), let product = number(productKey), crude > 0 else { return [] }
        return [AnalysisResult(label: String(localized: "Wiederfindung"), value: String(format: "%.0f %%", product / crude * 100))]
    }

    private func number(_ key: String) -> Double? {
        let v = value(key).replacingOccurrences(of: ",", with: ".")
        guard !v.isEmpty else { return nil }
        if let d = parseDecimal(v) { return d }
        return Double(v)   // "1e-5"
    }

    private static func signed(_ v: Double, digits: Int) -> String {
        let s = String(format: "%.\(digits)f", abs(v))
        return v < 0 ? "−" + s : (v > 0 ? "+" + s : s)
    }

    private static func grouped(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.maximumSignificantDigits = 3
        f.usesSignificantDigits = true
        return f.string(from: NSNumber(value: v))?.replacingOccurrences(of: ".", with: " ") ?? String(v)
    }

    // MARK: Zusammenfassung (eingeklappte Karte, PDF)

    /// Eine Zeile wie in einer Experimentalbeschreibung: "¹H-NMR (400 MHz, CDCl₃, 12 mg): δ = 7.26 (d, 2H)".
    var summary: String {
        func join(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: ", ") }
        func paren(_ parts: [String]) -> String { let j = join(parts); return j.isEmpty ? "" : " (\(j))" }
        func with(_ key: String, _ unit: String) -> String { let v = value(key); return v.isEmpty ? "" : "\(v) \(unit)" }
        let data = value("data")
        let notes = value("notes")
        var line: String
        switch method {
        case .nmr:
            let temp = value("temperature")
            line = heading + paren([with("frequency", "MHz"), value("solvent"), with("sampleMass", "mg"), temp.isEmpty ? "" : "\(temp) °C"])
            if !data.isEmpty { line += ": " + (data.hasPrefix("δ") ? data : "δ = " + data) }
        case .ir:
            line = "IR" + paren([value("technique")])
            if !data.isEmpty { line += ": " + (data.hasPrefix("ṽ") ? data : "ṽ = " + data) + (data.contains("cm") ? "" : " cm⁻¹") }
        case .uvVis:
            let c = value("concentration")
            line = "UV/Vis" + paren([value("solvent"), c.isEmpty ? "" : "c = \(c) mol/L", with("pathLength", "cm")])
            var parts: [String] = []
            if !value("lambdaMax").isEmpty {
                let eps = results.first.map { " (\($0.value))" } ?? ""
                parts.append("λmax = \(value("lambdaMax")) nm\(eps)")
            }
            if !data.isEmpty { parts.append(data) }
            if !parts.isEmpty { line += ": " + parts.joined(separator: "; ") }
        case .ms:
            line = heading + paren([value("ionization"), value("polarity")])
            var parts: [String] = []
            let ion = value("ion"), formula = value("formula")
            if !value("mzCalc").isEmpty || !value("mzFound").isEmpty {
                var s = "m/z"
                if !ion.isEmpty { s += " \(ion)" }
                if !value("mzCalc").isEmpty {
                    s += String(localized: " ber.") + (formula.isEmpty ? "" : String(localized: " für \(formula)")) + ": \(value("mzCalc"))"
                }
                if !value("mzFound").isEmpty { s += (value("mzCalc").isEmpty ? ": " : ", ") + String(localized: "gef.: ") + value("mzFound") }
                if let r = results.first { s += " (\(r.value))" }
                parts.append(s)
            } else if !formula.isEmpty {
                parts.append(formula)
            }
            if !data.isEmpty { parts.append(data) }
            if !parts.isEmpty { line += ": " + parts.joined(separator: "; ") }
        case .opticalRotation:
            // "Drehwert: [α]D²⁰ = +25.3 (c 1.00, CHCl₃); Literatur: +26.0; optische Reinheit 97 %"
            line = heading
            var parts: [String] = []
            if let specific = specificRotation {
                let given = value("specific")
                let shown = given.isEmpty ? Self.rotation(specific) : given
                let cond = [value("concentration").isEmpty ? "" : "c \(value("concentration"))", value("solvent")].filter { !$0.isEmpty }
                parts.append("\(rotationSymbol) = \(shown)" + (cond.isEmpty ? "" : " (\(cond.joined(separator: ", ")))"))
            } else if !value("measured").isEmpty {
                parts.append("α = \(value("measured"))°")
            }
            if !value("literature").isEmpty { parts.append(String(localized: "Literatur: \(value("literature"))")) }
            if let purity = results.first(where: { $0.label == String(localized: "Optische Reinheit") }) {
                parts.append(String(localized: "optische Reinheit \(purity.value)"))
            }
            if !parts.isEmpty { line += ": " + parts.joined(separator: "; ") }
        case .epr:
            // "CW-EPR (X-Band, 9.48 GHz, 2 mW, Mod. 0.2 mT/100 kHz, 77 K, gefrorene Lösung, Toluol, 1 mM): g = 2.0034; A(¹⁴N) = 42 MHz"
            let band = value("band").components(separatedBy: " (").first ?? ""
            var modulation = value("modAmp").isEmpty ? "" : String(localized: "Mod. \(value("modAmp")) mT")
            if !value("modFreq").isEmpty { modulation += (modulation.isEmpty ? String(localized: "Mod. ") : "/") + "\(value("modFreq")) kHz" }
            let scans = value("scans")
            line = heading + paren([band, with("frequency", "GHz"), with("power", "mW"), modulation, with("temperature", "K"),
                                    value("sampleState"), value("solvent"), with("concentration", "mM"),
                                    scans.isEmpty ? "" : String(localized: "\(scans) Scans")])
            var parts: [String] = []
            let g = value("gValues"), a = value("hyperfine"), zfs = value("zfs")
            if !g.isEmpty { parts.append(g.lowercased().hasPrefix("g") ? g : "g = " + g) }
            if !a.isEmpty { parts.append(a.hasPrefix("A") ? a : "A = " + a) }
            if !zfs.isEmpty { parts.append(zfs.hasPrefix("D") ? zfs : "D, E = " + zfs) }
            if !value("field").isEmpty { parts.append(String(localized: "Feld \(value("field"))")) }
            if !data.isEmpty { parts.append(data) }
            if !value("simulation").isEmpty { parts.append(String(localized: "Simulation: \(value("simulation"))")) }
            if !parts.isEmpty { line += ": " + parts.joined(separator: "; ") }
        default:
            // Übrige Methoden: alle ausgefüllten Felder als "Bezeichnung Wert Einheit", Bemerkungen am Ende
            let skip: Set<String> = method == .other ? ["title", "notes"] : ["notes"]
            let parts = method.fields.filter { !skip.contains($0.key) && !value($0.key).isEmpty }.map { f -> String in
                let v = value(f.key)
                return "\(f.label) \(v)\(f.unit.map { " \($0)" } ?? "")"
            } + results.map { "\($0.label) \($0.value)" }
            line = heading + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", "))
        }
        if !notes.isEmpty, method != .other { line += ". " + notes }
        if method == .other, !notes.isEmpty { line += ": " + notes }
        return line
    }

    /// Volltext für die Suche.
    var searchText: String {
        ([method.title, heading, sample] + values.values + files.flatMap { [$0.description, ($0.filePath as NSString).lastPathComponent] })
            .joined(separator: " ")
    }

    // MARK: Übernahme alter Dateien

    /// Ordnet eine früher verknüpfte Datei anhand von Beschreibung und Dateiname einer Methode zu.
    static func migrated(from file: AnalysisFile) -> AnalysisEntry {
        let text = (file.description + " " + (file.filePath as NSString).lastPathComponent).lowercased()
        func has(_ words: [String]) -> Bool {
            words.contains { w in text.range(of: "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: w) + "([^a-z]|$)", options: .regularExpression) != nil }
        }
        var entry: AnalysisEntry
        if has(["nmr", "1h", "13c", "19f", "31p", "11b", "cosy", "hsqc", "hmbc", "noesy", "fid"]) {
            entry = AnalysisEntry(method: .nmr)
            if has(["13c"]) { entry.values["nucleus"] = "¹³C{¹H}" }
            else if has(["19f"]) { entry.values["nucleus"] = "¹⁹F" }
            else if has(["31p"]) { entry.values["nucleus"] = "³¹P{¹H}" }
            else if has(["11b"]) { entry.values["nucleus"] = "¹¹B" }
            else if has(["cosy"]) { entry.values["nucleus"] = "COSY" }
            else if has(["hsqc"]) { entry.values["nucleus"] = "HSQC" }
            else if has(["hmbc"]) { entry.values["nucleus"] = "HMBC" }
            else if has(["noesy"]) { entry.values["nucleus"] = "NOESY" }
            else if has(["1h"]) { entry.values["nucleus"] = "¹H" }
        } else if has(["hrms", "ms", "esi", "maldi", "apci", "masse", "mass"]) {
            entry = AnalysisEntry(method: .ms)
            if has(["hrms"]) { entry.values["kind"] = "HRMS" }
        } else if has(["ir", "ftir", "atr"]) {
            entry = AnalysisEntry(method: .ir)
        } else if has(["uv", "uvvis", "uv-vis", "absorption"]) {
            entry = AnalysisEntry(method: .uvVis)
        } else if has(["gc", "gcms", "gc-ms"]) {
            entry = AnalysisEntry(method: .gc)
        } else if has(["dc", "tlc"]) {
            entry = AnalysisEntry(method: .tlc)
        } else {
            entry = AnalysisEntry(method: .other)
        }
        entry.files = [file]
        return entry
    }
}
