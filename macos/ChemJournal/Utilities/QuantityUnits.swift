import Foundation

// Anzeigeeinheiten für n, V und m in den Tabellen. Gespeichert wird immer in mol, ml und g (Dateiformat und
// alle Rechnungen bleiben gleich); die gewählte Einheit ändert nur, wie die Zahl angezeigt und eingegeben wird.

nonisolated enum QuantityKind: String, Sendable {
    case amount, volume, mass

    /// Einheiten zur Auswahl, die Basiseinheit zuerst.
    var units: [DisplayUnit] {
        switch self {
        case .amount: [DisplayUnit("mol", 1), DisplayUnit("mmol", 1e-3), DisplayUnit("µmol", 1e-6)]
        case .volume: [DisplayUnit("ml", 1), DisplayUnit("l", 1e3), DisplayUnit("µl", 1e-3)]
        case .mass: [DisplayUnit("g", 1), DisplayUnit("kg", 1e3), DisplayUnit("mg", 1e-3), DisplayUnit("µg", 1e-6)]
        }
    }

    var baseUnit: DisplayUnit { units[0] }

    /// Einheit zum gespeicherten Kürzel; Unbekanntes fällt auf die Basiseinheit zurück.
    func unit(_ symbol: String) -> DisplayUnit { units.first { $0.symbol == symbol } ?? baseUnit }
}

nonisolated struct DisplayUnit: Hashable, Sendable {
    let symbol: String
    /// Wert in der Basiseinheit = Wert in dieser Einheit × factor (1 mmol = 0.001 mol).
    let factor: Double
    init(_ symbol: String, _ factor: Double) { self.symbol = symbol; self.factor = factor }
    var isBase: Bool { factor == 1 }
}

nonisolated enum QuantityConversion {
    /// Gespeicherten Wert (Basiseinheit) in der Anzeigeeinheit darstellen. Nicht lesbare Eingaben bleiben, wie sie sind.
    static func display(_ base: String, in unit: DisplayUnit, kind: QuantityKind) -> String {
        guard !unit.isBase, let v = parseDecimal(base) else { return base }
        return format(v / unit.factor, kind: kind)
    }

    /// Eingabe in der Anzeigeeinheit in die Basiseinheit umrechnen. Leeres oder nicht Lesbares wird unverändert gespeichert.
    static func toBase(_ text: String, from unit: DisplayUnit) -> String {
        guard !unit.isBase, let v = parseDecimal(text) else { return text }
        return formatBase(v * unit.factor)
    }

    /// Zahl in einer Einheit mit derselben Genauigkeit wie in der Tabelle (n: 4 Stellen, V und m: 3 Stellen).
    static func format(_ v: Double, kind: QuantityKind) -> String {
        kind == .amount ? format4(v) : format3(v)
    }

    /// Umgerechnete Eingaben behalten bis zu 6 signifikante Stellen, damit "12.34 mg" nicht zu "0.0123 g" gerundet wird.
    private static func formatBase(_ v: Double) -> String {
        baseFormatter.string(from: NSNumber(value: v)) ?? String(v)
    }

    private static let baseFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = 6
        f.minimumSignificantDigits = 1
        return f
    }()
}
