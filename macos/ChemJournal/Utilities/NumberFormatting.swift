import Foundation

// Zahlenformatierung für die Tabellen. Feste Nachkommastellen, aber sehr kleine Werte behalten ihre
// signifikanten Stellen: 115 µmol werden als "0.000115" mol angezeigt statt als "0.0001".

nonisolated private let _fmt3: NumberFormatter = makeFormatter(fractionDigits: 3)
nonisolated private let _fmt4: NumberFormatter = makeFormatter(fractionDigits: 4)
nonisolated private let _sig3: NumberFormatter = makeFormatter(significantDigits: 3)
nonisolated private let _sig4: NumberFormatter = makeFormatter(significantDigits: 4)

nonisolated private func makeFormatter(fractionDigits: Int? = nil, significantDigits: Int? = nil) -> NumberFormatter {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.numberStyle = .decimal
    f.usesGroupingSeparator = false
    f.decimalSeparator = "."
    if let fractionDigits {
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = 0
    }
    if let significantDigits {
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = significantDigits
        f.minimumSignificantDigits = 1
    }
    return f
}

/// Masse (g) und Volumen (ml): drei Nachkommastellen, unter 0.1 drei signifikante Stellen.
nonisolated func format3(_ v: Double) -> String {
    let f = (v != 0 && abs(v) < 0.1) ? _sig3 : _fmt3
    return f.string(from: NSNumber(value: v)) ?? ""
}

/// Stoffmenge (mol) und Äquivalente: vier Nachkommastellen, unter 0.01 vier signifikante Stellen.
nonisolated func format4(_ v: Double) -> String {
    let f = (v != 0 && abs(v) < 0.01) ? _sig4 : _fmt4
    return f.string(from: NSNumber(value: v)) ?? ""
}

/// Liest "6.55", "6,55" und ".5". Gibt `nil` für alles andere zurück (auch "1e5", "1,4-" oder leere Strings).
nonisolated func parseDecimal(_ s: String) -> Double? {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    guard trimmed.range(of: #"^-?(?:\d+(?:[.,]\d*)?|[.,]\d+)$"#, options: .regularExpression) != nil else { return nil }
    return Double(trimmed.replacingOccurrences(of: ",", with: "."))
}
