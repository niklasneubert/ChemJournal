import Foundation

/// Bereinigt Synthesevorschriften, die aus PDFs kopiert wurden, bevor sie an den NLTagger gehen.
///
/// Typische PDF-Artefakte, die hier repariert werden:
/// - verklebte Wörter und Zahlen ("abgekühltund18.6 ml", "Lösungwurdeauf0 °C", "eq)einer2.5M")
/// - Ersatzzeichen für Grad und Minus ("0 •C", "auf–78•C")
/// - Silbentrennung am Zeilenende ("zuge-\ntropft", "n-Butyllithium-\nLösung")
/// - an Klammern klebende Substratnummern ("1.10 eq)4 addiert")
///
/// Chemische Formeln (CuSO4·5H2O, Pd(PPh3)4, Et3N), Verbindungsnummern (3b, 11c)
/// und Liganden-Kürzel (B2pin2) bleiben unverändert. Die Funktion ist idempotent.
nonisolated func normalizeSynthesisText(_ input: String) -> String {
    SynthesisTextNormalizer.normalize(input)
}

nonisolated enum SynthesisTextNormalizer {

    static func normalize(_ input: String) -> String {
        var s = cleanUnicode(input)
        s = repairLineBreaks(s)
        s = normalizeTemperatures(s)
        s = normalizeDashes(s)
        s = normalizeAdductDots(s)
        s = splitGluedSentences(s)
        s = healInlineHyphenation(s)
        // Beide Richtungen bedingen sich ("weiteren15Minutenwurde6.80"), daher bis zur Stabilität wiederholen
        for _ in 0..<3 {
            let before = s
            s = splitDigitsFromLetters(splitLettersFromDigits(s))
            if s == before { break }
        }
        s = splitBracketsAndCommas(s)
        s = splitGluedWords(s)
        // Nach dem Zerlegen können neue Wort-Zahl-Klebestellen sichtbar werden ("…Zeitraumvon1 h" → "… von 1 h")
        s = splitDigitsFromLetters(splitLettersFromDigits(s))
        s = tidyWhitespace(s)
        return s
    }

    // MARK: - 1. Unicode

    private static let ligatures: [String: String] = [
        "\u{FB00}": "ff", "\u{FB01}": "fi", "\u{FB02}": "fl", "\u{FB03}": "ffi", "\u{FB04}": "ffl",
        "\u{FB05}": "st", "\u{FB06}": "st",
    ]

    /// Zeichen aus dem PDF-Font "Symbol" landen beim Kopieren im Private-Use-Bereich U+F0xx.
    private static let symbolFont: [UInt32: String] = [
        0xF0B0: "°", 0xF06D: "µ", 0xF0B4: "×", 0xF0B1: "±", 0xF0A2: "′", 0xF0D7: "·", 0xF02D: "-", 0xF0BB: "≈",
        0xF0AE: "→", 0xF0D2: "", 0xF0E2: "", 0xF0D3: "", 0xF0E3: "", 0xF0D4: "", 0xF0E4: "",
        0xF061: "α", 0xF062: "β", 0xF063: "χ", 0xF064: "δ", 0xF065: "ε", 0xF066: "φ", 0xF067: "γ", 0xF068: "η",
        0xF06C: "λ", 0xF06E: "ν", 0xF070: "π", 0xF071: "θ", 0xF072: "ρ", 0xF073: "σ", 0xF074: "τ", 0xF077: "ω",
        0xF044: "Δ",
    ]

    static func cleanUnicode(_ input: String) -> String {
        var s = input.precomposedStringWithCanonicalMapping   // PDFs liefern Umlaute oft zerlegt (u + ¨)
        if s.unicodeScalars.contains(where: { $0.value >= 0xF000 && $0.value <= 0xF0FF }) {
            s = String(s.unicodeScalars.map { scalar -> String in
                if let mapped = symbolFont[scalar.value] { return mapped }
                return String(scalar)
            }.joined())
        }
        // Markenzeichen gehören nicht in den Namen ("Aquivion®PW98", "Celite®")
        s = replace(s, #"[\x{00AE}\x{2122}\x{00A9}]"#, "")
        s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        s = s.replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\u{2029}", with: "\n\n")
        for (lig, plain) in ligatures { s = s.replacingOccurrences(of: lig, with: plain) }
        // Weiches Trennzeichen am Zeilenende = Silbentrennung
        s = replace(s, #"\x{00AD}[ \t]*\n[ \t]*"#, "")
        s = replace(s, #"[\x{00AD}\x{200B}\x{200C}\x{200D}\x{2060}\x{FEFF}]"#, "")
        // Geschützte, schmale und typografische Leerzeichen
        s = replace(s, #"[\x{00A0}\x{2000}-\x{200A}\x{202F}\x{205F}\x{3000}\t]"#, " ")
        // Griechisches My → Mikro-Zeichen, damit "μL" und "µL" gleich behandelt werden
        s = s.replacingOccurrences(of: "\u{03BC}", with: "\u{00B5}")
        // LaTeX-PDFs (Computer Modern) liefern α beim Kopieren oft als "↵"
        s = s.replacingOccurrences(of: "\u{21B5}", with: "α")
        // Griechische Lokanten "α, α,4-trimethyl" → "α,α,4-trimethyl"
        s = replace(s, #"([α-ω]), (?=[α-ω][,\-′'])"#, "$1,")
        // Geschützte Bindestriche sind normale Bindestriche
        s = s.replacingOccurrences(of: "\u{2010}", with: "-").replacingOccurrences(of: "\u{2011}", with: "-")
        return s
    }

    // MARK: - 2. Zeilenumbrüche & Silbentrennung

    /// Präfixe, deren Bindestrich auch am Zeilenende erhalten bleibt ("tert-\nbutyl" → "tert-butyl").
    private static let chemicalPrefixes: Set<String> = [
        "n", "s", "t", "i", "o", "m", "p", "d", "l", "r", "e", "z", "tert", "sec", "iso", "neo", "cis", "trans",
        "endo", "exo", "syn", "anti", "rac", "meso", "ortho", "meta", "para", "bis", "tris", "tetrakis", "di", "tri",
    ]

    static func repairLineBreaks(_ input: String) -> String {
        var s = input
        // Trennstrich am Zeilenende, danach Kleinbuchstabe: Silbentrennung heilen
        s = replace(s, #"([A-Za-zÄÖÜäöüß]+)-[ \t]*\n[ \t]*([a-zäöüß])"#) { m in
            let left = m[1], right = m[2]
            let lastWord = left.lowercased()
            if chemicalPrefixes.contains(lastWord) { return "\(left)-\(right)" }
            return left + right
        }
        // Nummerierte Überschrift ("5.3.2 Silylketenacetal 5", "6. General procedures") bleibt ein eigener Absatz.
        // Zeilen mit Einheiten ("6.55 ml (46.5 mmol) …") sind Fließtext, auch wenn sie mit einer Zahl beginnen.
        s = replace(s, #"(?m)^([ \t]*(?:\d+\.)+\d*[ \t]+[A-ZÄÖÜ][a-zäöüß]{2,}[^\n]*)\n(?!\n)"#) { m in
            let line = m[1].trimmingCharacters(in: .whitespaces)
            let hasUnit = line.range(of: #"\d\s*(?:mmol|µmol|mol|mg|g|kg|ml|mL|µl|µL|l|L|eq|equiv|Äq|°C)(?![A-Za-z])"#, options: .regularExpression) != nil
            let isHeading = !hasUnit && line.count < 150 && !line.hasSuffix(".")
            return m[1] + (isHeading ? "\n\n" : "\n")
        }
        // Trennstrich am Zeilenende vor Großbuchstabe/Ziffer/Klammer: Bindestrich gehört zum Namen
        s = replace(s, #"-[ \t]*\n[ \t]*(?=[A-ZÄÖÜ0-9(\[])"#, "-")
        // Einzelne Umbrüche sind PDF-Zeilenenden → Leerzeichen; Leerzeilen bleiben Absatzgrenzen
        s = replace(s, #"[ \t]*\n[ \t]*\n[\s]*"#, "\u{E000}")
        s = replace(s, #"[ \t]*\n[ \t]*"#, " ")
        s = s.replacingOccurrences(of: "\u{E000}", with: "\n\n")
        return s
    }

    // MARK: - 3. Temperatur

    static func normalizeTemperatures(_ input: String) -> String {
        // Manche PDF-Schriften liefern Grad und Minus als Pfeil: "→78→C" → "-78→C"
        var s = replace(input, #"→(?=\d+(?:[.,]\d+)?[ ]*→[ ]*[CFK](?![A-Za-zÄÖÜäöüß0-9]))"#, "-")
        // "0 •C", "–78•C", "25 ºC", "25 ˚C", "25 ◦C", "25° C", "0 →C" → "25 °C"
        s = replace(s, #"(\d)[ ]*[°º˚◦∘•∙⁰→¶][ ]*([CFK])(?![A-Za-zÄÖÜäöüß0-9])"#, "$1 °$2")
        // "bei0°Ctropfenweise" → "bei0 °C tropfenweise"
        s = replace(s, #"(\d)[ ]*[°¶][ ]*([CFK])(?=[a-zäöüß]{3,})"#, "$1 °$2 ")
        return s
    }

    // MARK: - 4. Striche

    static func normalizeDashes(_ input: String) -> String {
        var s = input
        let dashes = "[\u{2012}\u{2013}\u{2014}\u{2015}\u{2212}\u{FE58}\u{FE63}\u{FF0D}]"
        // Bereiche "20 – 25 °C" → "20-25 °C"
        s = replace(s, #"(\d)[ ]*\#(dashes)[ ]*(?=\d)"#, "$1-")
        // Vorzeichen "– 78 °C" / "–78" → "-78"
        s = replace(s, #"\#(dashes)[ ]*(?=\d)"#, "-")
        // Bindestrich in Namen "Dess–Martin" → "Dess-Martin"
        s = replace(s, #"(?<=[A-Za-zÄÖÜäöüß0-9)\]])\#(dashes)(?=[A-Za-zÄÖÜäöüß(\[])"#, "-")
        // Minus klebt an einem Wort: "auf-78 °C" → "auf -78 °C"
        s = replace(s, #"(?<=[A-Za-zÄÖÜäöüß])-(?=\d+(?:[.,]\d+)?[ ]?°[CFK])"#, " -")
        return s
    }

    // MARK: - 5. Addukt-/Hydratpunkte

    static func normalizeAdductDots(_ input: String) -> String {
        var s = input
        // "CuSO4 • 5 H2O", "BH3 ∙ THF", "BF3⋅OEt2" → Mittelpunkt ohne Leerzeichen
        s = replace(s, #"(?<=[A-Za-z0-9)\]])[ ]*[•∙⋅·][ ]*(?=[A-Za-z0-9(\[])"#, "·")
        // "·5 H2O" → "·5H2O"
        s = replace(s, #"·(\d+)[ ]+(?=H2O\b)"#, "·$1")
        return s
    }

    // MARK: - 6. Verklebte Satzgrenzen

    static func splitGluedSentences(_ input: String) -> String {
        // "zugetropft.Nach" → "zugetropft. Nach" (kein Eingriff in Dezimalzahlen oder Abkürzungen wie "z.B.")
        replace(input, #"(?<=[a-zäöüß]{3}|\))\.(?=[A-ZÄÖÜ][a-zäöüß])"#, ". ")
    }

    // MARK: - 7. Silbentrennung innerhalb einer Zeile ("zuge-tropft")

    private static let participleRegex = try! NSRegularExpression(
        pattern: #"^(?:hinzu|zusammen|zu|ab|auf|aus|an|ein|nach|weg|vor|bei|mit|um|unter|über|durch)?ge[a-zäöüß]{3,}(?:t|en)$"#)
    private static let inseparableVerbRegex = try! NSRegularExpression(
        pattern: #"^(?:ver|ent|zer|be|er)[a-zäöüß]{3,}t$|^[a-zäöüß]{3,}iert$"#)

    static func healInlineHyphenation(_ input: String) -> String {
        replace(input, #"(?<![A-Za-zÄÖÜäöüß-])([A-Za-zÄÖÜäöüß][a-zäöüß]+)-([a-zäöüß]{2,})(?![A-Za-zÄÖÜäöüß-])"#) { m in
            let joined = (m[1] + m[2]).lowercased()
            if chemicalPrefixes.contains(m[1].lowercased()) { return m[0] }
            if SynthesisLexicon.words.contains(joined) || matches(participleRegex, joined) || matches(inseparableVerbRegex, joined) {
                return m[1] + m[2]
            }
            return m[0]
        }
    }

    // MARK: - 8. Buchstaben | Ziffer ("und18.6", "wurde6.80", "einer2.5M")

    /// Ligand- und Schutzgruppen-Kürzel, bei denen die folgende Ziffer zur Formel gehört (B2pin2, Pd2dba3).
    private static let formulaSuffixes = [
        "pin", "dba", "cod", "acac", "dppf", "dppe", "dppp", "dppb", "bpy", "bipy", "terpy", "ppy", "phen", "dtbbpy",
        "tmeda", "dmpe", "salen", "moc", "boc", "cbz", "troc", "alloc", "dmso", "tmhd", "hfacac", "nbd", "dipp", "mes",
    ]

    static func splitLettersFromDigits(_ input: String) -> String {
        replace(input, #"(?<![A-Za-zÄÖÜäöüß0-9])([A-ZÄÖÜa-zäöüß]?[a-zäöüß]{3,})(?=\d)"#) { m in
            let word = m[1].lowercased()
            if formulaSuffixes.contains(where: { word.hasSuffix($0) }) { return m[0] }
            return m[1] + " "
        }
    }

    // MARK: - 9. Ziffer | Buchstaben ("298.0mg", "15Minuten", "2.5M")

    /// Einheiten mit mindestens zwei Zeichen sind eindeutig und werden immer abgetrennt.
    private static let longUnits = [
        "mmol", "µmol", "umol", "nmol", "mol-%", "mol%", "mol", "mg", "µg", "ug", "kg", "mL", "ml", "µL", "µl", "uL", "ul",
        "mM", "eq", "Eq", "equiv", "Äq", "äq", "Äquiv", "äquiv", "min", "bar", "atm", "mbar", "Torr", "wt%",
    ]

    static func splitDigitsFromLetters(_ input: String) -> String {
        var s = input
        let units = longUnits.sorted { $0.count > $1.count }.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // Mehrbuchstabige Einheiten
        s = replace(s, #"(?<![A-Za-z])(\d+(?:[.,]\d+)?)(?=(?:\#(units))(?![A-Za-zÄÖÜäöüß0-9]))"#, "$1 ")
        // Einbuchstabige Einheiten nur nach Dezimalzahlen ("2.5M", "0.98L", "1.5g") –
        // "3g" oder "4h" können Verbindungsnummern sein und bleiben stehen.
        s = replace(s, #"(?<![A-Za-z0-9.,])(\d+[.,]\d+)(?=[gLlMhN](?![A-Za-zÄÖÜäöüß0-9]))"#, "$1 ")
        // Liter in Großschreibung ist nie eine Verbindungsnummer ("2L Rundkolben")
        s = replace(s, #"(?<![A-Za-z0-9.,])(\d+)(?=L(?![A-Za-zÄÖÜäöüß0-9]))"#, "$1 ")
        // Einheit klebt am folgenden Namen: "36.0mLBr2" → "36.0 mL Br2", "76.0mlCHCl3" → "76.0 ml CHCl3"
        s = replace(s, #"(?<![A-Za-z0-9.,])(\d+(?:[.,]\d+)?)[ ]?(mL|ml|mg|kg|mmol|µmol|µL|µl|g|L)(?=[A-Z][A-Za-z0-9(])"#, "$1 $2 ")
        // Einheit klebt am folgenden Adjektiv/Wort: "60mLtrockenem DMF" → "60 mL trockenem DMF"
        s = replace(s, #"(\d+(?:[.,]\d+)?)(mL|ml|mg|g|L|mmol)([a-zäöüß]{3,})"#) { m in
            SynthesisLexicon.words.contains(m[3].lowercased()) ? "\(m[1]) \(m[2]) \(m[3])" : m[0]
        }
        // Kurzes Funktionswort klebt an einer Zahl: "in1000 mL" → "in 1000 mL"
        s = replace(s, #"(?<![A-Za-zÄÖÜäöüß0-9])(in|im|zu|um|am|an|mit|von|und|of|to|at|by)(?=\d)"#, "$1 ")
        // Zahl klebt an einem Wort ("15Minuten", "6.80wurde")
        s = replace(s, #"(?<![A-Za-z0-9])(\d+(?:[.,]\d+)?)(?=[A-ZÄÖÜa-zäöüß][a-zäöüß]{2,})"#, "$1 ")
        return s
    }

    // MARK: - 10. Klammern und Kommata

    /// Klammerinhalt sieht nach Mengenangabe aus ("46.5 mmol, 0.95 eq") und nicht nach Formel ("PPh3").
    private static let quantityContent = try! NSRegularExpression(
        pattern: #"\d\s*(?:mmol|µmol|umol|mol|mg|µg|kg|g|mL|ml|µL|µl|L|l|eq|Eq|equiv|Äq|äq|Äquiv|%|M)(?![A-Za-z0-9])"#)

    static func splitBracketsAndCommas(_ input: String) -> String {
        var s = input
        // ")4", ")einer" → ") 4", ") einer" – nur wenn die Klammer eine Mengenangabe schließt
        s = replace(s, #"\(([^()]*)\)(?=[A-Za-zÄÖÜäöüß0-9])"#) { m in
            matches(quantityContent, m[1]) ? m[0] + " " : m[0]
        }
        // "Diisopropylamin(6.55 ml, …)" → "Diisopropylamin (6.55 ml, …)"
        s = replace(s, #"(?<=[A-Za-zÄÖÜäöüß0-9])\(([^()]*)\)"#) { m in
            matches(quantityContent, m[1]) ? " " + m[0] : m[0]
        }
        // "mmol,0.95" und "eq,THF" → mit Leerzeichen; "1,4-Dioxan", "6,55" und "N,N" bleiben
        s = replace(s, #"(?<=[a-zµ%.)\]]),(?=[A-Za-zÄÖÜäöüß0-9(])"#, ", ")
        s = replace(s, #";(?=\S)"#, "; ")
        return s
    }

    // MARK: - 11. Verklebte Wörter ("Lösungwurdeauf", "addiertunddieLösung")

    static func splitGluedWords(_ input: String) -> String {
        replace(input, #"[A-Za-zÄÖÜäöüß]{6,}"#) { m in
            SynthesisLexicon.segment(m[0]) ?? m[0]
        }
    }

    // MARK: - 12. Leerraum

    static func tidyWhitespace(_ input: String) -> String {
        var s = replace(input, #" {2,}"#, " ")
        s = replace(s, #" *\n *"#, "\n")
        s = replace(s, #"\n{3,}"#, "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Regex-Helfer

    private static var cache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    private static func regex(_ pattern: String) -> NSRegularExpression {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let r = cache[pattern] { return r }
        let r = try! NSRegularExpression(pattern: pattern)
        cache[pattern] = r
        return r
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        regex(pattern).stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Ersetzt jeden Treffer durch das Ergebnis der Closure; `m[0]` ist der Treffer, `m[1…]` die Gruppen.
    static func replace(_ s: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        let re = regex(pattern)
        let ns = s as NSString
        var out = ""
        var last = 0
        for match in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            out += transform(groups)
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
