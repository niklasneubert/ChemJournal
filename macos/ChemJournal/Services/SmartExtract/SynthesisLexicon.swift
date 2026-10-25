import Foundation

/// Wortschatz typischer Synthesevorschriften (deutsch und englisch).
///
/// Wird für zwei Dinge genutzt:
/// 1. Zerlegen von Wörtern, die beim PDF-Kopieren zusammengeklebt sind ("Lösungwurdeauf" → "Lösung wurde auf").
/// 2. Heilen von Silbentrennungen ("zuge-tropft" → "zugetropft").
///
/// Bewusst enthält die Liste keine Chemikalien-Wortteile ("stoff", "säure", …), damit Namen wie
/// "Wasserstoffperoxid" oder "Reaktionslösung" nie zerlegt werden.
nonisolated enum SynthesisLexicon {

    /// Geschlossene Wortklassen: Artikel, Präpositionen, Konjunktionen, Hilfsverben.
    /// Eine Zerlegung wird nur akzeptiert, wenn mindestens eines dieser Wörter darin vorkommt.
    static let functionWords: Set<String> = [
        // Deutsch
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "eines", "einem", "einen",
        "und", "oder", "sowie", "mit", "von", "vom", "zu", "zum", "zur", "in", "im", "auf", "an", "am", "bei", "beim",
        "nach", "für", "über", "unter", "aus", "bis", "durch", "gegen", "ohne", "um", "als", "wie", "wurde", "wurden",
        "wird", "werden", "ist", "sind", "war", "waren", "hat", "haben", "es", "sich", "so", "dann", "noch", "weitere",
        "weiteren", "weiterer", "anschließend", "danach", "dabei", "dazu", "hierzu", "zunächst", "nun", "erneut",
        "zusätzlich", "langsam", "unter", "sowie", "dieser", "diese", "dieses", "diesem", "diesen",
        // Englisch
        "the", "a", "an", "and", "or", "of", "to", "in", "into", "on", "at", "by", "for", "with", "from", "was",
        "were", "is", "are", "then", "after", "over", "under", "this", "that", "which", "it", "as", "further",
        "additional", "slowly", "again", "until",
    ]

    /// Inhaltswörter aus Vorschriften. Nur ganze Einträge zählen als bekannte Wörter.
    static let contentWords: Set<String> = [
        // Deutsch: Verben und Partizipien
        "vorgelegt", "zugegeben", "hinzugegeben", "zugefügt", "hinzugefügt", "addiert", "zugetropft", "hinzugetropft",
        "getropft", "gelöst", "aufgelöst", "erhalten", "gerührt", "nachgerührt", "abgekühlt", "gekühlt", "erwärmt",
        "erhitzt", "gekocht", "refluxiert", "filtriert", "abfiltriert", "gewaschen", "getrocknet", "extrahiert",
        "eingeengt", "entfernt", "versetzt", "behandelt", "suspendiert", "verdünnt", "neutralisiert", "angesäuert",
        "gequencht", "aufgearbeitet", "gereinigt", "umkristallisiert", "destilliert", "abdestilliert", "isoliert",
        "eingewogen", "gegeben", "gegossen", "überführt", "kombiniert", "vereinigt", "getrennt", "gelagert",
        "belassen", "gehalten", "gebracht", "erreicht", "gestartet", "beendet", "verfolgt", "kontrolliert",
        "entgast", "evakuiert", "begast", "gespült", "geschüttelt", "ausgefallen", "gefällt", "zersetzt",
        "tropfenweise", "portionsweise", "rühren", "lösen", "geben", "wurde", "wurden", "gerührten",
        // Deutsch: Nomen und Adjektive aus Vorschriften
        "lösung", "lösungen", "gemisch", "reaktionsgemisch", "mischung", "phase", "phasen", "rückstand", "suspension",
        "minute", "minuten", "stunde", "stunden", "tag", "tage", "tagen", "sekunden", "nacht", "temperatur",
        "raumtemperatur", "rückfluss", "argon", "stickstoff", "atmosphäre", "schutzgas", "kolben", "rundkolben",
        "reaktion", "zugabe", "ausbeute", "produkt", "feststoff", "öl", "farbe", "trockenem", "trockenen", "absolutem",
        "wasserfreiem", "wasserfreien", "absolutem", "trockenen", "frisch", "abs", "dest", "organische", "organischen", "wässrige", "wässrigen", "gesättigte",
        "gesättigter", "langsam", "vorsichtig", "sofort", "insgesamt", "weitere", "weiteren", "folgenden",
        "anschließend", "abschließend", "zusammen", "genau", "zeitraum", "jeweils", "portionen", "spritze",
        // Englisch: Verben
        "added", "dissolved", "stirred", "cooled", "warmed", "heated", "refluxed", "filtered", "washed", "dried",
        "extracted", "concentrated", "evaporated", "removed", "treated", "diluted", "quenched", "neutralized",
        "acidified", "purified", "recrystallized", "distilled", "isolated", "obtained", "afforded", "gave",
        "combined", "separated", "transferred", "charged", "placed", "kept", "maintained", "allowed", "stirring",
        "dropwise", "portionwise", "sequentially", "introduced", "suspended", "degassed", "evacuated", "backfilled",
        // Englisch: Nomen und Adjektive
        "solution", "solutions", "mixture", "phase", "residue", "suspension", "minute", "minutes", "hour", "hours",
        "day", "days", "night", "overnight", "temperature", "room", "reflux", "argon", "nitrogen", "atmosphere",
        "flask", "reaction", "addition", "yield", "product", "solid", "oil", "dry", "anhydrous", "organic",
        "aqueous", "saturated", "slowly", "carefully", "immediately", "together",
    ]

    /// Wörter, die wie Zusammensetzungen aussehen, aber nie zerlegt werden dürfen.
    static let neverSplit: Set<String> = [
        "inden", "indem", "indan", "undecan", "undecanol", "undecen", "andere", "anderen", "anderer", "indol",
        "indium", "anilin", "aniline", "another", "within", "without", "thereafter", "therefore", "however",
        "afterwards", "overnight", "together", "whereupon", "herein", "daraufhin", "nachdem", "sodass", "wodurch",
        "worauf", "wobei", "womit", "dabei", "zudem", "außerdem", "hierbei", "insgesamt", "daran", "darin",
        "zwischen", "während", "bevor", "nachher", "vorher", "ausbeute", "aufarbeitung", "anschließend",
        "abschließend", "zunächst", "zusammen", "sowohl", "beiden", "diesem", "dieses", "dieser",
    ]

    /// Alle bekannten Wörter (kleingeschrieben).
    static let words: Set<String> = functionWords.union(contentWords).union(neverSplit)

    private static let participle = try! NSRegularExpression(
        pattern: #"^(?:hinzu|zusammen|zu|ab|auf|aus|an|ein|nach|weg|vor|bei|mit|um)?ge[a-zäöüß]{3,}(?:t|en)$|^[a-zäöüß]{3,}iert$"#)

    private static func isParticiple(_ w: String) -> Bool {
        participle.firstMatch(in: w, range: NSRange(w.startIndex..., in: w)) != nil
    }

    /// Zerlegt ein verklebtes Wort in bekannte Wörter. Gibt `nil` zurück, wenn das Wort ganz bleiben soll.
    ///
    /// Regeln (bewusst konservativ):
    /// - Bekannte Wörter und Wörter aus `neverSplit` bleiben ganz.
    /// - Jeder Teil muss ein bekanntes Wort sein, mit zwei Ausnahmen: ein unbekannter Teil, der mitten im Wort
    ///   mit einem Großbuchstaben beginnt ("vonDiisopropylamin"), oder ein deutsches Partizip ("hinzugetropftund").
    /// - Mindestens ein Teil muss ein Funktionswort sein (verhindert "Eis|bad", "Raum|temperatur").
    /// - Kein Teil darf kürzer als zwei Buchstaben sein.
    static func segment(_ token: String) -> String? {
        let lower = token.lowercased()
        if words.contains(lower) || neverSplit.contains(lower) { return nil }
        let chars = Array(token)
        let lowerChars = Array(lower)
        let n = chars.count
        guard n >= 6, lowerChars.count == n else { return nil }

        // best[i] = beste Zerlegung von chars[0..<i]: (Anzahl Teile, Anzahl unbekannter Teile, Grenzen, enthält Funktionswort)
        struct Path { var parts: Int; var unknown: Int; var cuts: [Int]; var hasFunction: Bool }
        var best = [Path?](repeating: nil, count: n + 1)
        best[0] = Path(parts: 0, unknown: 0, cuts: [0], hasFunction: false)

        for end in 2...n {
            for start in stride(from: end - 2, through: 0, by: -1) {
                guard let prev = best[start] else { continue }
                let piece = String(lowerChars[start..<end])
                var isKnown = words.contains(piece)
                var isFunction = functionWords.contains(piece)
                // Ein-Buchstaben-Funktionswörter wie "a" nicht als Teil zulassen
                if piece.count < 2 { isKnown = false; isFunction = false }
                var unknownOK = false
                if !isKnown {
                    let startsUpperInside = start > 0 && chars[start].isUppercase && piece.count >= 3
                    let participleAtStart = start == 0 && piece.count >= 6 && isParticiple(piece)
                    unknownOK = startsUpperInside || participleAtStart
                }
                guard isKnown || unknownOK else { continue }
                let candidate = Path(parts: prev.parts + 1,
                                     unknown: prev.unknown + (isKnown ? 0 : 1),
                                     cuts: prev.cuts + [end],
                                     hasFunction: prev.hasFunction || isFunction)
                if candidate.unknown > 1 { continue }
                if let current = best[end] {
                    // Weniger unbekannte Teile, dann weniger Teile bevorzugen
                    if (candidate.unknown, candidate.parts) < (current.unknown, current.parts) { best[end] = candidate }
                } else {
                    best[end] = candidate
                }
            }
        }

        // Deutsche Flexionsendungen nicht als eigenes Wort abtrennen ("umkristallisiert|es")
        let germanEndings: Set<String> = ["es", "er", "em", "en", "an", "am", "im", "in", "ab"]
        if let path = best[n], path.parts >= 2, path.hasFunction,
           !germanEndings.contains(String(lowerChars[path.cuts[path.cuts.count - 2]..<n])) {
            var pieces: [String] = []
            for i in 0..<(path.cuts.count - 1) {
                pieces.append(String(chars[path.cuts[i]..<path.cuts[i + 1]]))
            }
            return pieces.joined(separator: " ")
        }
        return splitUnknownPrefix(chars: chars, lower: lowerChars)
    }

    /// Partizipien, die als Wortende eines Kompositums vorkommen und kein eigenes Wort sind ("Wassergehalt").
    private static let compoundTails: Set<String> = ["gehalt", "gemisch", "gewicht", "gefäß", "gerät", "gebiet", "geruch", "gestell"]

    /// Unbekannter Name am Anfang, gefolgt von bekannten Wörtern: "Diisopropylaminvorgelegtundbei" →
    /// "Diisopropylamin vorgelegt und bei". Der Rest muss entweder aus mindestens zwei bekannten Wörtern mit
    /// einem Funktionswort bestehen oder genau ein Partizip sein ("THFvorgelegt") – und in jedem Fall ein Verb
    /// enthalten. Komposita wie "Reaktionslösung", "Natriumsulfatlösung" oder "Dreihalskolben" bleiben so ganz.
    private static func splitUnknownPrefix(chars: [Character], lower: [Character]) -> String? {
        let n = chars.count
        guard n >= 8 else { return nil }
        for k in 3...(n - 5) {
            // Chemische Endungen ("-amin", "-in", "-an") nicht als Funktionswort abschneiden: erstes Wort ≥ 3 Buchstaben
            guard let rest = knownSegmentation(Array(lower[k...])), rest[0].count >= 3,
                  !["es", "er", "em", "en", "an", "am", "im", "in", "ab"].contains(rest[rest.count - 1]) else { continue }
            let hasFunction = rest.contains { functionWords.contains($0) }
            // Typische PDF-Verklebung: Name + Verb ("…amin|vorgelegt|und|bei"). Ohne Verb ist es eher ein
            // Kompositum ("Dreihals|kolben") und bleibt ganz.
            let hasVerb = rest.contains { w in
                w.count >= 5 && !compoundTails.contains(where: { w.hasSuffix($0) }) && (isParticiple(w) || (w.hasSuffix("ed") && contentWords.contains(w)))
            }
            let okRest = hasVerb && (rest.count == 1 || hasFunction)
            guard okRest else { continue }
            var pieces = [String(chars[0..<k])]
            var pos = k
            for word in rest { pieces.append(String(chars[pos..<(pos + word.count)])); pos += word.count }
            return pieces.joined(separator: " ")
        }
        return nil
    }

    /// Zerlegung ausschließlich in bekannte Wörter (min. 2 Buchstaben), mit möglichst wenigen Teilen.
    private static func knownSegmentation(_ chars: [Character]) -> [String]? {
        let n = chars.count
        var best = [[String]?](repeating: nil, count: n + 1)
        best[0] = []
        for end in 2...max(2, n) where end <= n {
            for start in stride(from: end - 2, through: 0, by: -1) {
                guard let prev = best[start] else { continue }
                let piece = String(chars[start..<end])
                guard words.contains(piece) else { continue }
                if best[end] == nil || prev.count + 1 < best[end]!.count { best[end] = prev + [piece] }
            }
        }
        return best[n]
    }
}
