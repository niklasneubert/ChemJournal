import Foundation

/// Wandelt "(12)" in fette Verbindungsnummern und "\ce{H2O}" in Unicode-Tief-/Hochstellung um.
func applySmartFormatting(to text: String) -> String {
    var result = text
    if let regex = try? NSRegularExpression(pattern: "\\(([0-9]+)\\)") {
        let boldMap: [Character: Character] = ["0":"\u{1D7CE}","1":"\u{1D7CF}","2":"\u{1D7D0}","3":"\u{1D7D1}","4":"\u{1D7D2}","5":"\u{1D7D3}","6":"\u{1D7D4}","7":"\u{1D7D5}","8":"\u{1D7D6}","9":"\u{1D7D7}"]
        for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            if let range = Range(match.range, in: result) {
                var s = ""; for c in String(result[range]) where c.isNumber { s.append(boldMap[c] ?? c) }
                result.replaceSubrange(range, with: s)
            }
        }
    }
    if let ceRegex = try? NSRegularExpression(pattern: "\\\\ce\\{([^}]+)\\}") {
        let subMap: [Character: Character] = ["0":"\u{2080}","1":"\u{2081}","2":"\u{2082}","3":"\u{2083}","4":"\u{2084}","5":"\u{2085}","6":"\u{2086}","7":"\u{2087}","8":"\u{2088}","9":"\u{2089}"]
        let supMap: [Character: Character] = ["0":"\u{2070}","1":"\u{00B9}","2":"\u{00B2}","3":"\u{00B3}","4":"\u{2074}","5":"\u{2075}","6":"\u{2076}","7":"\u{2077}","8":"\u{2078}","9":"\u{2079}","+":"\u{207A}","-":"\u{207B}"]
        for match in ceRegex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            if let fullRange = Range(match.range(at: 0), in: result), let contentRange = Range(match.range(at: 1), in: result) {
                var out = ""; var sup = false
                for c in String(result[contentRange]) {
                    if c == "^" { sup = true; continue }
                    if sup { if let s = supMap[c] { out.append(s) } else { out.append(c); sup = false } }
                    else if c.isNumber { out.append(subMap[c] ?? c) } else { out.append(c) }
                }
                result.replaceSubrange(fullRange, with: out)
            }
        }
    }
    return result
}

/// Entschärft Nutzertext für den HTML-Export (Titel mit "<" oder "&" zerstörten bisher das Layout).
nonisolated func htmlEscaped(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

/// Dateiname ohne Zeichen, die macOS-Pfade brechen ("/" und ":").
nonisolated func safeFileName(_ s: String, fallback: String = "Ansatz") -> String {
    let cleaned = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? fallback : cleaned
}
