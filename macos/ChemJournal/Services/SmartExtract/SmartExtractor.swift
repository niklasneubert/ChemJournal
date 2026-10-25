import Foundation
import NaturalLanguage

/// Wandelt eine Synthesevorschrift in Zeilen der Ansatzgrößen-Tabelle um.
///
/// Ablauf:
/// 1. `normalizeSynthesisText` repariert PDF-Artefakte.
/// 2. `NLTagger` zerlegt den Text in Tokens und versieht sie – falls ein Modell geladen ist – mit den
///    Create-ML-Klassen CHEMICAL, MASS, AMOUNT, VOLUME, EQ, NONE.
/// 3. Ein deterministischer Parser liest Zahl + Einheit, ordnet Mengen den Namen zu und filtert
///    Temperaturen, Zeiten, Konzentrationen, Kolbengrößen und Aufarbeitungsschritte heraus.
///
/// Das Modell entscheidet nur, welche Wörter Chemikaliennamen sind. Mengen erkennt der Parser selbst,
/// weil Einheiten eindeutig sind und Regeln hier zuverlässiger sind als jede Vorhersage.
nonisolated struct SmartExtractor {

    /// Create-ML-Modell (optional). Ohne Modell entscheidet eine Heuristik, was ein Chemikalienname ist.
    let model: NLModel?

    init(model: NLModel? = nil) { self.model = model }

    func extract(from rawText: String) -> [ChemicalData] {
        let text = normalizeSynthesisText(rawText)
        guard !text.isEmpty else { return [] }
        let words = Self.groupIntoWords(tokens: tokenize(text), in: text)
        var parser = Parser(text: text, words: words)
        return parser.run()
    }

    // MARK: - Tokenisierung

    struct Token {
        let text: String
        let range: Range<String.Index>
        let tag: String?
    }

    /// Ein "Wort" sind Tokens, die nur durch Bindezeichen ohne Leerraum verbunden sind:
    /// "n-Butyllithium-Lösung", "Pd(PPh3)4", "CuSO4·5H2O", "1,4-dioxane", "°C".
    struct Word {
        var tokens: [Token]
        let gapBefore: Substring
        var range: Range<String.Index> { tokens.first!.range.lowerBound..<tokens.last!.range.upperBound }
        var tags: [String] { tokens.compactMap(\.tag) }
    }

    static let modelScheme = NLTagScheme("ChemJournalExtract")

    func tokenize(_ text: String) -> [Token] {
        let whole = text.startIndex..<text.endIndex
        let scheme: NLTagScheme = model == nil ? .tokenType : Self.modelScheme
        let tagger = NLTagger(tagSchemes: [scheme])
        tagger.string = text
        if let model {
            tagger.setModels([model], forTagScheme: scheme)
            // Ohne diese Zeile erkennt NLTagger deutschen Text und wendet das (englisch trainierte) Modell gar nicht an.
            if let language = model.configuration.language { tagger.setLanguage(language, range: whole) }
        }
        var tokens: [Token] = []
        tagger.enumerateTags(in: whole, unit: .word, scheme: scheme, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            tokens.append(Token(text: String(text[range]), range: range, tag: model == nil ? nil : tag?.rawValue))
            return true
        }
        return tokens
    }

    private static let joinerCharacters = CharacterSet(charactersIn: "-()[]/·'’′″,+")

    static func groupIntoWords(tokens: [Token], in text: String) -> [Word] {
        var words: [Word] = []
        var previousEnd = text.startIndex
        for token in tokens {
            let gap = text[previousEnd..<token.range.lowerBound]
            let joins = !words.isEmpty && gap.unicodeScalars.allSatisfy { joinerCharacters.contains($0) }
            if joins {
                words[words.count - 1].tokens.append(token)
            } else {
                words.append(Word(tokens: [token], gapBefore: gap))
            }
            previousEnd = token.range.upperBound
        }
        return words
    }
}

// MARK: - Parser

nonisolated extension SmartExtractor {

    enum QuantityKind { case mass, amount, volume, eq }

    struct PartialRow {
        var nameRange: Range<String.Index>?
        var mass: Double?
        var amount: Double?
        var volume: Double?
        var eq: Double?
        var hasQuantity: Bool { mass != nil || amount != nil || volume != nil || eq != nil }
        func has(_ kind: QuantityKind) -> Bool {
            switch kind {
            case .mass: mass != nil
            case .amount: amount != nil
            case .volume: volume != nil
            case .eq: eq != nil
            }
        }
        mutating func set(_ kind: QuantityKind, _ value: Double) {
            switch kind {
            case .mass: mass = value
            case .amount: amount = value
            case .volume: volume = value
            case .eq: eq = value
            }
        }
    }

    struct Parser {
        let text: String
        let words: [Word]
        var rows: [ChemicalData] = []
        var current = PartialRow()
        var nameOpen = false
        /// Startpunkt eines Namenspräfixes wie "10%" in "10% Pd/C".
        var pendingNameStart: String.Index?
        /// Name wurde durch ein Stoppwort beendet, bevor Mengen kamen ("In trockenem THF wurden 3.39 g …").
        /// Folgende Mengen gehören dann zur nächsten Chemikalie.
        var nameClosedByStopword = false
        /// "a solution of X in CH2Cl2 (1.43 M, 9.8 mL)": X wurde durch "in" beendet, danach kam das Lösemittel.
        var sawInAfterName = false
        var solventAfterIn = false
        var lastFlushed: PartialRow?
        /// Klammertiefe im aktuellen Satz. In Einschüben ("(1:1 mixture of regioisomers)") beenden Stoppwörter keinen Namen.
        var parenDepth = 0
        /// Zuletzt verworfenes Wort. Folgt darauf "(Menge …)", war es doch ein Name ("Natriumascorbat (19.8 mg)").
        var lastRejectedWord: Word?

        init(text: String, words: [Word]) {
            self.text = text
            self.words = words
        }

        mutating func run() -> [ChemicalData] {
            for sentence in splitSentences() {
                flush()
                parenDepth = 0
                let firstRow = rows.count
                for clause in splitClauses(sentence) where !isWorkupOrProduct(clause) {
                    parse(clause)
                    flush()
                }
                // Sätze ganz ohne Mengen (Überschriften, NMR-Daten, "unter Argon") liefern keine Tabellenzeilen
                if !rows[firstRow...].contains(where: \.hasAnyQuantity) { rows.removeSubrange(firstRow...) }
            }
            return rows
        }

        // MARK: Sätze

        private func splitSentences() -> [ArraySlice<Word>] {
            var result: [ArraySlice<Word>] = []
            var start = 0
            for i in words.indices where i > 0 && isSentenceBoundary(before: i) {
                result.append(words[start..<i])
                start = i
            }
            if start < words.count { result.append(words[start..<words.count]) }
            return result
        }

        private func isSentenceBoundary(before i: Int) -> Bool {
            let gap = words[i].gapBefore
            if gap.contains("\n") || gap.contains(";") { return true }
            // NLTagger hängt den Satzpunkt manchmal ans Token: "… bei 0 °C. The mixture", "… 30 min. Danach"
            if let lastToken = words[i - 1].tokens.last?.text, lastToken.count > 1, lastToken.hasSuffix("."),
               gap.contains(where: \.isWhitespace), let first = text[words[i].range].first, first.isUppercase || first.isNumber {
                let stem = String(lastToken.dropLast()).lowercased()
                if !Vocabulary.abbreviations.contains(stem) && !stem.contains(".") { return true }
            }
            if gap.contains(":"), text[words[i].range].first?.isUppercase == true { return true }
            // Punkt direkt gefolgt von Leerraum; "equiv.)" oder "abs. THF" sind keine Satzenden
            guard let dot = gap.firstIndex(of: "."), gap[gap.index(after: dot)...].first?.isWhitespace ?? true else { return false }
            let previous = text[words[i - 1].range].lowercased()
            return !Vocabulary.abbreviations.contains(previous)
        }

        /// Teilt einen Satz an starken Teilsatzgrenzen: ", which", "and then", ", and the", ", followed by", "und anschließend" …
        /// So geht bei "X (5 g) was dissolved in SOCl2 (25 mL), which was heated … and then concentrated" nur der letzte Teil verloren.
        private func splitClauses(_ sentence: ArraySlice<Word>) -> [ArraySlice<Word>] {
            var result: [ArraySlice<Word>] = []
            var start = sentence.startIndex
            func lower(_ i: Int) -> String { i < sentence.endIndex ? text[sentence[i].range].lowercased() : "" }
            for i in sentence.indices where i > start {
                let comma = sentence[i].gapBefore.contains(",")
                let w = lower(i), next = lower(i + 1)
                let boundary = (comma && Vocabulary.clauseOpeners.contains(w))
                    || (["and", "und"].contains(w) && ["then", "anschließend", "danach", "dann"].contains(next))
                    || (comma && ["and", "und"].contains(w) && ["the", "die", "der", "das", "to", "zu"].contains(next))
                if boundary { result.append(sentence[start..<i]); start = i }
            }
            result.append(sentence[start..<sentence.endIndex])
            return result
        }

        private func isWorkupOrProduct(_ clause: ArraySlice<Word>) -> Bool {
            let lowers = clause.map { text[$0.range].lowercased() }
            if lowers.contains(where: { Vocabulary.workupWords.contains($0) }) { return true }
            // "crude product", "crude residue" – aber nicht "crude (6.0 g, …) tris-diol" als Edukt
            for (a, b) in zip(lowers, lowers.dropFirst()) where a == "crude" && ["product", "residue", "mixture", "material", "oil", "solid", "aldehyde", "ketone", "alcohol", "diol"].contains(b) { return true }
            // "saturated aqueous NH4Cl", "ges. NaHCO3-Lösung", "brine"
            let saturated = lowers.contains { ["saturated", "sat", "gesättigter", "gesättigte", "gesättigtem", "ges"].contains($0) }
            if saturated && lowers.contains(where: { w in ["aqueous", "aq", "wässriger", "wässrige", "nh4cl", "nahco3", "nacl", "na2s2o3"].contains(where: { w.hasPrefix($0) }) || w.hasSuffix("-lösung") }) { return true }
            // Verdünnen ohne Reagenzzugabe ist Aufarbeitung ("The reaction mixture was diluted with DCM (100 mL) …")
            if lowers.contains(where: { ["diluted", "verdünnt"].contains($0) })
                && !lowers.contains(where: { Vocabulary.reactionVerbs.contains($0) }) { return true }
            return false
        }

        // MARK: Wortweise Verarbeitung

        private mutating func parse(_ sentence: ArraySlice<Word>) {
            var i = sentence.startIndex
            var skipCarrier = false   // "(2.5 M in hexanes, …)": Lösemittel des Reagenzes überspringen
            while i < sentence.endIndex {
                let word = sentence[i]
                let wordText = String(text[word.range])
                let lower = wordText.lowercased()

                if word.gapBefore.contains(",") || word.gapBefore.contains("(") || word.gapBefore.contains(")") {
                    nameOpen = false
                    skipCarrier = false
                }
                // Klammern vor und innerhalb des Wortes zählen ("((4R,5S)-5-(…)methyl)…methanol" ist in sich ausgeglichen)
                let span = text[word.gapBefore.startIndex..<word.range.upperBound]
                parenDepth = max(0, parenDepth + span.filter { $0 == "(" }.count - span.filter { $0 == ")" }.count)
                if skipCarrier { i += 1; continue }
                let rejectedBefore = lastRejectedWord
                lastRejectedWord = nil

                // Zahl (+ Einheit)
                if word.tokens.count == 1, let value = parseDecimal(wordText) {
                    // Name-zuerst-Schreibweise mit unbekanntem Namen: "Natriumascorbat (19.8 mg, …)"
                    if word.gapBefore.contains("("), current.nameRange == nil, !current.hasQuantity,
                       let candidate = rejectedBefore, i > sentence.startIndex, candidate.range == sentence[i - 1].range {
                        addNameWord(candidate)
                    }
                    i = handleNumber(value, at: i, in: sentence, skipCarrier: &skipCarrier)
                    continue
                }
                // Zahl und Einheit in einem Token ("298.0mg"), falls die Normalisierung sie nicht getrennt hat
                if word.tokens.count == 1, let (value, unit) = SmartExtractor.splitGluedQuantity(wordText),
                   let quantity = Units.quantity(unit, gapAfter: "") {
                    setQuantity(quantity.kind, value * quantity.factor)
                    i += 1
                    continue
                }

                // Stoppwörter schließen den aktuellen Namen
                if word.tokens.count == 1, Vocabulary.stopwords.contains(lower) {
                    nameOpen = false
                    pendingNameStart = nil
                    if lower == "in" && parenDepth > 0 && current.nameRange != nil { skipCarrier = true }
                    if lower == "in" && parenDepth == 0 && current.nameRange != nil && !current.hasQuantity { sawInAfterName = true }
                    if parenDepth == 0 {
                        if current.nameRange != nil && !current.hasQuantity { nameClosedByStopword = true }
                        if current.nameRange != nil && current.hasQuantity { flush() }
                    }
                    i += 1
                    continue
                }

                if SmartExtractor.isCompoundLabel(wordText) {
                    if acceptCompoundLabel(at: i, in: sentence) { addLabelWord(word, at: i, in: sentence) } else { nameOpen = false; lastRejectedWord = word }
                    i += 1
                    continue
                }

                // Kurzname in Klammern direkt nach dem Namen: "ethyl acetate (EtOAc, 2.0 mL)"
                if word.gapBefore.contains("("), current.nameRange != nil, !current.hasQuantity,
                   i + 1 < sentence.endIndex, sentence[i + 1].gapBefore.contains(",") {
                    i += 1
                    continue
                }

                if isChemicalName(word, text: wordText) {
                    addNameWord(word)
                } else {
                    nameOpen = false
                    pendingNameStart = nil
                    lastRejectedWord = word
                }
                i += 1
            }
        }

        /// Verarbeitet eine Zahl und gibt den Index des nächsten unverarbeiteten Wortes zurück.
        private mutating func handleNumber(_ value: Double, at i: Int, in sentence: ArraySlice<Word>, skipCarrier: inout Bool) -> Int {
            let numberWord = sentence[i]
            // Portionsgröße: "in Portionen zu jeweils ca. 0.5 g", "in portions of 100 mg each"
            let before = sentence[max(sentence.startIndex, i - 3)..<i].map { text[$0.range].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            if before.contains(where: { ["jeweils", "je", "each", "portionen", "portions", "portion"].contains($0) }) {
                if i + 1 < sentence.endIndex, Units.quantity(String(text[sentence[i + 1].range]), gapAfter: "") != nil { return i + 2 }
                return i + 1
            }
            // "a solution of n-BuLi in hexane (1.44 mL, 3.6 mmol)": enthält die Klammer nach dem Lösemittel eine
            // Stoffmenge oder Konzentration, gehören die Mengen zum gelösten Stoff davor
            if parenDepth > 0, solventAfterIn, !current.hasQuantity, let previous = lastFlushed, !previous.hasQuantity,
               let last = rows.last, !last.hasAnyQuantity, parenGroupHasAmount(from: i, in: sentence) {
                rows.removeLast()
                current = previous
                solventAfterIn = false
            }
            let next = i + 1 < sentence.endIndex ? sentence[i + 1] : nil
            let nextText = next.map { String(text[$0.range]) } ?? ""
            let gapToNext = next?.gapBefore ?? ""
            let gapAfterNext = i + 2 < sentence.endIndex ? sentence[i + 2].gapBefore : Substring(text[(next?.range.upperBound ?? text.endIndex)...].prefix(3))

            // Prozentangabe direkt an der Zahl: "10% Pd/C" ist Teil des Namens
            if gapToNext.hasPrefix("%") {
                pendingNameStart = numberWord.range.lowerBound
                return i + 1
            }
            // Temperatur "-78 °C", "0 °C"
            if nextText.hasPrefix("°") { return i + 2 }

            let unitAdjacent = next != nil && gapToNext.allSatisfy(\.isWhitespace)
            if unitAdjacent, let quantity = Units.quantity(nextText, gapAfter: gapAfterNext) {
                if quantity.kind == .volume, isApparatus(after: i + 1, in: sentence) { return i + 2 }
                setQuantity(quantity.kind, value * quantity.factor)
                return i + 2
            }
            if unitAdjacent, Units.isConcentration(nextText) {
                // "2.5 M in hexanes" – das Lösemittel gehört zum Reagenz, nicht in die Tabelle
                if i + 2 < sentence.endIndex, text[sentence[i + 2].range].lowercased() == "in" { skipCarrier = true }
                return i + 2
            }
            if unitAdjacent, Units.isIgnoredUnit(nextText) { return i + 2 }

            // Ganze Zahl ohne Einheit: Verbindungsnummer ("1.10 eq) 4 addiert", "von 7")
            let raw = String(text[numberWord.range])
            if SmartExtractor.isCompoundLabel(raw), acceptCompoundLabel(at: i, in: sentence) {
                addLabelWord(numberWord, at: i, in: sentence)
            } else {
                nameOpen = false
                if SmartExtractor.isCompoundLabel(raw) { lastRejectedWord = numberWord }
            }
            return i + 1
        }

        /// Steht in der aktuellen Klammer (ab Wort i bis ")") eine Stoffmenge oder Konzentration?
        private func parenGroupHasAmount(from i: Int, in sentence: ArraySlice<Word>) -> Bool {
            var j = i
            while j < sentence.endIndex {
                if j > i && sentence[j].gapBefore.contains(")") { break }
                let w = String(text[sentence[j].range])
                if Units.isConcentration(w) { return true }
                if let q = Units.quantity(w, gapAfter: ""), q.kind == .amount { return true }
                j += 1
            }
            return false
        }

        /// Kolben- oder Gefäßvolumen: "in einem 250 mL Kolben", "a 25 mL round-bottom flask".
        private func isApparatus(after unitIndex: Int, in sentence: ArraySlice<Word>) -> Bool {
            for j in (unitIndex + 1)..<min(unitIndex + 3, sentence.endIndex) {
                let w = text[sentence[j].range].lowercased()
                if Vocabulary.apparatus.contains(where: { w.contains($0) }) { return true }
            }
            return false
        }

        private func acceptCompoundLabel(at i: Int, in sentence: ArraySlice<Word>) -> Bool {
            // Nach Mengenangaben ohne Namen: "6.80 ml (53.8 mmol, 1.10 eq) 4 addiert"
            if current.hasQuantity && current.nameRange == nil { return true }
            // Direkt hinter einem Namen: "aldehyde 1", "Trimethylsilylchlorid 4"
            if nameOpen && sentence[i].gapBefore.allSatisfy(\.isWhitespace) { return true }
            // Nach einem einleitenden Wort: "von 7", "compound 3b", "Verbindung 12"
            if i > sentence.startIndex {
                let previous = text[sentence[i - 1].range].lowercased()
                if Vocabulary.labelIntroducers.contains(previous) { return true }
            }
            return false
        }

        // MARK: Namen

        /// Verbindungsnummer übernehmen; nach einem Nomen ("starting material 1", "Verbindung 12") gehört das Nomen dazu.
        private mutating func addLabelWord(_ word: Word, at i: Int, in sentence: ArraySlice<Word>) {
            if !nameOpen, i > sentence.startIndex,
               word.gapBefore.allSatisfy(\.isWhitespace) {
                let previous = sentence[i - 1]
                let prevText = text[previous.range].lowercased()
                if Vocabulary.labelNouns.contains(prevText) {
                    var start = previous.range.lowerBound
                    // Ein Attribut davor ("starting material", "aryl iodide") ebenfalls übernehmen
                    if i - 1 > sentence.startIndex, previous.gapBefore.allSatisfy(\.isWhitespace) {
                        let before = sentence[i - 2]
                        let beforeText = text[before.range].lowercased()
                        if !Vocabulary.stopwords.contains(beforeText), parseDecimal(beforeText) == nil,
                           beforeText.allSatisfy(\.isLetter) { start = before.range.lowerBound }
                    }
                    pendingNameStart = start
                }
            }
            addNameWord(word)
        }

        private func isChemicalName(_ word: Word, text wordText: String) -> Bool {
            let lower = wordText.lowercased()
            if Vocabulary.apparatus.contains(where: { lower.contains($0) }) { return false }
            if lower.range(of: #"^\d+(?:[.,]\d+)?-?(?:ml|l|µl|ul|g|mg|mmol|mol|eq)$"#, options: .regularExpression) != nil { return false }
            // Verweise auf Arbeitsvorschriften: "AAV-1", "GP2", "AAV 3"
            if lower.range(of: #"^(?:aav|gp|av|sop|gsp)-?\d"#, options: .regularExpression) != nil { return false }
            if Units.quantity(lower, gapAfter: "") != nil || Units.isIgnoredUnit(lower) { return false }
            let tags = word.tags
            if tags.contains("CHEMICAL") { return true }
            if !tags.isEmpty && tags.allSatisfy({ ["MASS", "AMOUNT", "VOLUME", "EQ"].contains($0) }) { return false }
            return nameOpen ? ChemicalHeuristics.looksLikeContinuation(wordText) : ChemicalHeuristics.looksLikeChemical(wordText)
        }

        private mutating func addNameWord(_ word: Word) {
            let afterIn = sawInAfterName && current.nameRange != nil && !nameOpen
            let pendingStart = pendingNameStart
            if current.nameRange != nil && !nameOpen { flush() }
            pendingNameStart = pendingStart
            solventAfterIn = afterIn
            sawInAfterName = false
            if let range = current.nameRange, nameOpen {
                current.nameRange = range.lowerBound..<word.range.upperBound
            } else {
                let start = pendingNameStart ?? word.range.lowerBound
                current.nameRange = start..<word.range.upperBound
            }
            pendingNameStart = nil
            nameOpen = true
            nameClosedByStopword = false
        }

        private mutating func setQuantity(_ kind: QuantityKind, _ value: Double) {
            if current.has(kind) || (nameClosedByStopword && !current.hasQuantity) { flush() }
            current.set(kind, value)
            nameOpen = false
            pendingNameStart = nil
        }

        // MARK: Zeile abschließen

        private mutating func flush() {
            let flushedRow = current
            defer {
                lastFlushed = flushedRow
                current = PartialRow(); nameOpen = false; pendingNameStart = nil; nameClosedByStopword = false
            }
            var name = current.nameRange.map { balancedName(for: $0) } ?? ""
            var wasSolution = false
            for suffix in Vocabulary.solutionSuffixes where name.lowercased().hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                wasSolution = true
                break
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:"))
            while name.hasPrefix("-") { name.removeFirst() }
            if Vocabulary.stopwords.contains(name.lowercased()) { name = "" }

            guard !name.isEmpty || current.hasQuantity else { return }
            // Namenlose Einzelangabe ("ca. 0.5 g") ist fast immer Rauschen; ab zwei Mengen bleibt sie zum Nachtragen stehen
            let quantityCount = [current.mass, current.amount, current.volume, current.eq].compactMap { $0 }.count
            if name.isEmpty && quantityCount < 2 { return }
            // Reines Trägerlösemittel ohne Mengen ("als THF-Lösung zugetropft") nicht übernehmen
            if !current.hasQuantity && wasSolution { return }

            var row = ChemicalData()
            row.name = name
            if let v = current.eq { row.equivalents = format4(v) }
            if let v = current.amount { row.amount = format4(v) }
            if let v = current.volume { row.volume = format3(v) }
            if let v = current.mass { row.mass = format3(v) }
            rows.append(row)
        }

        /// Liefert den Namen aus dem Originaltext und ergänzt dabei abgeschnittene Klammern: "S)-BINOL" → "(S)-BINOL".
        private func balancedName(for range: Range<String.Index>) -> String {
            var lower = range.lowerBound
            var upper = range.upperBound
            func count(_ c: Character) -> Int { text[lower..<upper].filter { $0 == c }.count }
            while count(")") > count("("), lower > text.startIndex, text[text.index(before: lower)] == "(" {
                lower = text.index(before: lower)
            }
            while count("(") > count(")"), upper < text.endIndex, text[upper] == ")" {
                upper = text.index(after: upper)
            }
            var name = String(text[lower..<upper])
            // Verbleibende Klammern am Rand, die keinen Partner haben, entfernen
            while name.hasSuffix(")") && name.filter({ $0 == ")" }).count > name.filter({ $0 == "(" }).count { name.removeLast() }
            while name.hasPrefix("(") && name.filter({ $0 == "(" }).count > name.filter({ $0 == ")" }).count { name.removeFirst() }
            return name
        }
    }

    // MARK: - Hilfsfunktionen

    static func isCompoundLabel(_ s: String) -> Bool {
        s.range(of: #"^[1-9]\d{0,2}[a-z]?$"#, options: .regularExpression) != nil
    }

    static func splitGluedQuantity(_ s: String) -> (Double, String)? {
        guard let match = s.range(of: #"^\d+(?:[.,]\d+)?"#, options: .regularExpression) else { return nil }
        let unit = String(s[match.upperBound...])
        guard unit.count >= 2, let value = parseDecimal(String(s[match])) else { return nil }
        return (value, unit)
    }
}

// MARK: - Einheiten

nonisolated enum Units {
    struct Quantity { let kind: SmartExtractor.QuantityKind; let factor: Double }

    /// Basis: Masse in g, Stoffmenge in mol, Volumen in ml, Äquivalente dimensionslos.
    private static let table: [String: Quantity] = [
        "mg": .init(kind: .mass, factor: 1e-3), "µg": .init(kind: .mass, factor: 1e-6), "ug": .init(kind: .mass, factor: 1e-6),
        "g": .init(kind: .mass, factor: 1), "kg": .init(kind: .mass, factor: 1e3),
        "mmol": .init(kind: .amount, factor: 1e-3), "µmol": .init(kind: .amount, factor: 1e-6), "umol": .init(kind: .amount, factor: 1e-6),
        "nmol": .init(kind: .amount, factor: 1e-9), "mol": .init(kind: .amount, factor: 1),
        "ml": .init(kind: .volume, factor: 1), "µl": .init(kind: .volume, factor: 1e-3), "ul": .init(kind: .volume, factor: 1e-3),
        "l": .init(kind: .volume, factor: 1e3), "cm3": .init(kind: .volume, factor: 1),
        "eq": .init(kind: .eq, factor: 1), "equiv": .init(kind: .eq, factor: 1), "equivs": .init(kind: .eq, factor: 1),
        "equivalent": .init(kind: .eq, factor: 1), "equivalents": .init(kind: .eq, factor: 1),
        "äq": .init(kind: .eq, factor: 1), "äquiv": .init(kind: .eq, factor: 1), "äquivalente": .init(kind: .eq, factor: 1),
    ]

    static func quantity(_ rawUnit: String, gapAfter: Substring) -> Quantity? {
        let unit = rawUnit.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        // "mol%" / "mol-%" → Äquivalente
        let gap = gapAfter.drop(while: { $0 == " " })
        if unit == "mol" && (gap.hasPrefix("%") || gap.hasPrefix("-%")) { return .init(kind: .eq, factor: 0.01) }
        if unit == "mol%" || unit == "mol-%" { return .init(kind: .eq, factor: 0.01) }
        return table[unit]
    }

    /// Molarität/Normalität: "2.5 M", "1 N", "0.5 mol/L", "100 mM".
    static func isConcentration(_ rawUnit: String) -> Bool {
        ["M", "N", "mM", "µM"].contains(rawUnit) || ["mol/l", "mol/dm3", "mmol/l"].contains(rawUnit.lowercased())
    }

    private static let ignored: Set<String> = [
        "min", "mins", "minute", "minuten", "minutes", "h", "hr", "hrs", "std", "stunde", "stunden", "hour", "hours",
        "s", "sec", "sekunden", "seconds", "d", "tag", "tage", "day", "days", "bar", "mbar", "atm", "torr", "psi", "pa",
        "kpa", "hpa", "nm", "w", "mw", "rpm", "upm", "å", "k", "x", "×", "mhz", "ppm", "wt", "gew",
    ]

    static func isIgnoredUnit(_ rawUnit: String) -> Bool { ignored.contains(rawUnit.lowercased()) }
}

// MARK: - Wortlisten

nonisolated enum Vocabulary {
    static let stopwords: Set<String> = [
        // Deutsch
        "vorgelegt", "zugegeben", "hinzugegeben", "addiert", "zugetropft", "hinzugetropft", "getropft", "gelöst", "gerührt",
        "nachgerührt", "abgekühlt", "gekühlt", "erwärmt", "erhitzt", "versetzt", "behandelt", "suspendiert", "verdünnt",
        "gegeben", "eingewogen", "kombiniert", "vereinigt", "zugefügt", "hinzugefügt", "überführt", "refluxiert",
        "die", "der", "das", "den", "dem", "des", "ein", "eine", "einer", "eines", "einem", "einen", "in", "im", "zu", "zum",
        "zur", "von", "vom", "nach", "mit", "auf", "bei", "für", "über", "unter", "aus", "als", "und", "oder", "sowie",
        "es", "wurde", "wurden", "wird", "werden", "dazu", "hierzu", "zunächst", "anschließend", "danach", "dann",
        "weiteren", "weitere", "langsam", "tropfenweise", "portionsweise", "vorsichtig", "sofort", "erneut", "zusätzlich",
        "minuten", "stunden", "min", "h", "lösung", "lösungen", "gemisch", "reaktionsgemisch", "mischung", "phase",
        "suspension", "trockenem", "trockenen", "trockenes", "wasserfreiem", "wasserfreien", "absolutem", "abs",
        "frisch", "destilliertem", "entgastem", "kolben", "rundkolben", "raumtemperatur", "rt", "rückfluss", "argon",
        "stickstoff", "schutzgas", "atmosphäre", "dieser", "diese", "dieses", "diesem", "letztes", "zuletzt", "nun",
        "insgesamt", "jeweils", "ca", "etwa", "gesättigter", "gesättigte", "ges", "wässriger", "wässrige", "konz",
        "konzentrierte", "konzentrierter", "verdünnte", "verdünnter", "brauner", "weißer", "gelber", "feststoff",
        "öl", "reaktion", "zugabe", "beginn", "ende", "rühren", "kühlen", "erwärmen",
        // Englisch
        "added", "stirred", "dissolved", "cooled", "warmed", "heated", "treated", "diluted", "suspended", "charged",
        "introduced", "sequentially", "combined", "placed", "transferred", "dropwise", "portionwise", "slowly",
        "the", "a", "an", "to", "of", "in", "into", "on", "at", "by", "for", "with", "from", "and", "or", "then",
        "after", "over", "under", "was", "were", "is", "are", "this", "that", "which", "it", "as", "further",
        "additional", "again", "solution", "solutions", "mixture", "reaction", "flask", "vial", "tube", "room",
        "temperature", "reflux", "dry", "anhydrous", "freshly", "distilled", "degassed", "nitrogen", "atmosphere",
        "minutes", "hours", "hour", "minute", "overnight", "sat", "saturated", "aq", "aqueous", "conc",
        "concentrated", "solid", "oil", "until", "followed", "successively", "portion", "portions", "one",
        // Analytik und Labor-Kürzel
        "nmr", "tlc", "dc", "hplc", "gc", "ms", "ir", "uv", "led", "aav", "esi", "hrms", "rf", "ph", "smp", "mp",
        "1h", "13c", "19f", "31p", "dest", "anhyd", "crude", "technical", "grade", "purity", "reinheit", "technisch", "mineralöl", "mineral", "paraffin", "suspension", "wt", "gew",
    ]

    /// Beginnen nach einem Komma einen neuen Teilsatz.
    static let clauseOpeners: Set<String> = [
        "which", "then", "followed", "whereupon", "before", "prior", "anschließend", "danach", "wobei", "bevor", "worauf",
        "woraufhin", "nachdem",
    ]

    /// Zugabe-Verben: Ein Teilsatz mit "verdünnt"/"diluted" und einem dieser Verben ist ein Reaktionsschritt.
    static let reactionVerbs: Set<String> = [
        "treated", "added", "addiert", "zugegeben", "versetzt", "zugetropft", "behandelt", "hinzugegeben", "hinzugefügt",
        "zugefügt",
    ]

    /// Wörter, die einen Aufarbeitungs- oder Produktsatz kennzeichnen. Diese Sätze landen nicht in der Tabelle.
    static let workupWords: Set<String> = [
        "extrahiert", "extracted", "gewaschen", "washed", "getrocknet", "dried", "filtriert", "abfiltriert", "filtered",
        "eingeengt", "eingedampft", "abrotiert", "concentrated", "evaporated", "gequencht", "quenched", "gereinigt",
        "purified", "chromatographiert", "chromatographed", "umkristallisiert", "recrystallized", "eluiert", "eluted",
        "erhalten", "obtained", "afforded", "furnished", "yielded", "isoliert", "isolated", "ergab", "lieferte",
        "aufgearbeitet", "dekantiert", "decanted", "beendet", "ausbeute", "yield", "rohprodukt", "rohproduktes",
        "erhielt", "quench", "quenching", "poured", "gegossen", "silica", "kieselgel", "slurry", "brine",
        "filtration", "evaporation", "extraction", "eingedampft", "rotiert",
    ]

    /// Abkürzungen, deren Punkt kein Satzende ist.
    static let abbreviations: Set<String> = [
        "eq", "equiv", "äq", "äquiv", "abs", "ca", "approx", "conc", "konz", "ges", "sat", "aq", "wässr", "bzw", "vgl",
        "resp", "ref", "nr", "no", "fig", "abb", "tab", "lit", "et", "al", "e.g", "i.e", "z.b", "u.a", "techn", "dest", "anhyd",
        "frisch", "ca", "vs", "wt",
    ]

    static let labelIntroducers: Set<String> = labelNouns.union(["von", "of", "nr", "no"])

    /// Nomen, auf die typischerweise eine Verbindungsnummer folgt ("starting material 1", "Bromid 7").
    static let labelNouns: Set<String> = [
        "compound", "verbindung", "substrat", "substrate", "edukt", "ester", "amin", "amine", "alkohol", "alcohol",
        "aldehyd", "aldehyde", "material", "startmaterial", "salt", "salz", "ketone", "keton", "bromide", "bromid",
        "iodide", "iodid", "acid", "säure", "amide", "amid", "alkyne", "alkin", "alkene", "olefin", "intermediate",
        "zwischenprodukt", "precursor", "vorstufe", "ligand", "catalyst", "katalysator", "complex", "komplex",
        "diol", "epoxide", "epoxid", "azide", "azid", "triflate", "triflat", "sulfonamide", "sulfonamid", "enone", "enon",
        "acetylene", "alkyne", "nitrile", "nitril", "sulfone", "sulfon", "phenylsulfone", "carbonate", "carbonat", "tosylate",
        "mesylate", "boronate", "lactone", "lacton", "imine", "imin", "oxime", "oxim", "sulfide", "thiol", "phenol", "aniline",
        "anilin", "indole", "indol", "pyridine", "pyridin", "olefine", "alcohols", "esters", "derivative", "derivat", "nitrone",
    ]

    static let apparatus = [
        "kolben", "flask", "vial", "tube", "gefäß", "reaktor", "reactor", "schlenk", "ampulle", "ampoule", "autoklav",
        "autoclave", "trichter", "funnel", "spritze", "syringe", "becherglas", "beaker", "atmosph", "ballon", "balloon",
    ]

    static let solutionSuffixes = ["-lösung", " lösung", "-solution", " solution", "-suspension", " suspension"]
}

// MARK: - Heuristik für Chemikaliennamen

/// Entscheidet ohne Modell (oder wenn das Modell ein Wort nicht als CHEMICAL markiert), ob ein Wort
/// wie ein Chemikalienname aussieht. Lieber ein Name zu wenig als ein Füllwort zu viel.
nonisolated enum ChemicalHeuristics {

    private static let knownNames: Set<String> = [
        "wasser", "water", "iod", "iodine", "jod", "brom", "bromine", "chlor", "zink", "zinc", "kupfer", "copper",
        "eisen", "iron", "ammoniak", "ammonia", "harnstoff", "urea", "chloroform", "aceton", "acetone", "ether",
        "äther", "diethylether", "dioxan", "dioxane", "hexan", "hexane", "hexanes", "heptan", "heptane", "pentan",
        "pentane", "pentanes", "toluol", "toluene", "benzol", "benzene", "xylol", "xylene", "acetonitril",
        "acetonitrile", "essigester", "ethylacetat", "pyridin", "pyridine", "oxone", "celite", "selectfluor",
        "triphosgen", "triphosgene", "phosgen", "phosgene", "formalin", "paraformaldehyd", "hydrazin", "hydrazine",
        "magnesium", "lithium", "natrium", "kalium", "sodium", "potassium", "palladium", "platin", "platinum",
        "nickel", "raney", "dess-martin", "periodinan", "periodinane", "grubbs", "wilkinson", "lawesson", "burgess",
        "mesyl", "tosyl", "trityl", "benzyl", "allyl", "vinyl", "phenyl", "methyl", "ethyl", "propyl", "butyl",
        "isopropanol", "methanol", "ethanol", "butanol", "propanol", "glycerin", "glycerol", "dichlormethan",
        "dichloromethane", "chlorbenzol", "chlorobenzene", "piperidin", "piperidine", "morpholin", "morpholine",
        "imidazol", "imidazole", "triethylamin", "triethylamine", "anilin", "aniline",
    ]

    private static let suffixes = [
        "amin", "amine", "amid", "amide", "imid", "imide", "anol", "enol", "anon", "anone", "enon", "enone", "ol",
        "säure", "acid", "ester", "ether", "aldehyd", "aldehyde", "keton", "ketone", "nitril", "nitrile",
        "chlorid", "chloride", "bromid", "bromide", "iodid", "iodide", "jodid", "fluorid", "fluoride", "hydrid",
        "hydride", "oxid", "oxide", "sulfid", "sulfide", "cyanid", "cyanide", "azid", "azide", "hydroxid", "hydroxide",
        "carbonat", "carbonate", "sulfat", "sulfate", "sulfit", "sulfite", "nitrat", "nitrate", "nitrit", "nitrite",
        "phosphat", "phosphate", "acetat", "acetate", "formiat", "formate", "triflat", "triflate", "tosylat",
        "tosylate", "mesylat", "mesylate", "borat", "borate", "chromat", "chromate", "perchlorat", "perchlorate",
        "hydrat", "hydrate", "ium", "benzol", "benzene", "toluol", "pyridin", "pyridine", "furan", "thiophen",
        "thiophene", "indol", "indole", "phenol", "anilin", "aniline", "methan", "ethan", "propan", "butan", "pentan",
        "hexan", "heptan", "octan", "decan", "ane", "oate", "oic", "ylat", "ylate", "silan", "silane", "stannan",
        "boran", "borane", "phosphin", "phosphine", "phosphan", "oxim", "oxime", "hydrazon", "hydrazone", "lacton",
        "lactone", "lactam", "imin", "imine", "azol", "azole", "azin", "azine", "idin", "idine", "olin", "oline",
        "yl", "pulver", "staub", "späne", "chips", "periodinan", "periodinane",
    ]

    /// Häufige Metalle/Elemente als eigenständige Namen ("Pd", "Zn") und in Formeln wie "Pd/C".
    private static let elementSymbols: Set<String> = [
        "Pd", "Pt", "Zn", "Mg", "Cu", "Fe", "Na", "Li", "Ni", "Rh", "Ru", "Ir", "Au", "Ag", "Sn", "Al", "Se", "Mn",
        "Cr", "Hg", "Pb", "Cs", "Sm", "Ce", "Si", "Ti", "Co", "Os", "Zr", "Sc", "Yb", "In",
    ]
    private static let cationPrefixes = [
        "natrium", "kalium", "lithium", "cäsium", "caesium", "cesium", "calcium", "magnesium", "ammonium", "tetrabutylammonium",
        "silber", "kupfer", "eisen", "zink", "palladium", "platin", "nickel", "cobalt", "kobalt", "mangan", "chrom",
        "barium", "aluminium", "titan", "zinn", "quecksilber", "blei", "sodium", "potassium", "silver",
    ]
    private static let singleLetterElements: Set<String> = ["C", "H", "N", "O", "S", "P", "I", "K", "B", "F"]

    /// Endungen, die als zweites Wort eines mehrteiligen Namens akzeptiert werden ("sodium ascorbate").
    private static let continuationSuffixes = ["ate", "ite", "ide", "ine", "ane", "ene", "yne", "one", "ol", "al", "salt", "complex", "sieves", "monohydrate", "dihydrate", "hydrochloride"]

    static func looksLikeChemical(_ raw: String) -> Bool {
        let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        guard !word.isEmpty else { return false }
        let lower = word.lowercased()
        if Vocabulary.stopwords.contains(lower) { return false }

        // Zusammengesetzte Wörter: ein chemischer Teil genügt ("n-Butyllithium", "THF-Lösung", "Pd/C")
        let parts = word.split(whereSeparator: { "-()[]/·,'’+".contains($0) }).map(String.init)
        if parts.count > 1 {
            if ["n", "s", "t", "i", "o", "m", "p", "sec", "tert", "iso", "cis", "trans", "rac", "bis", "tris", "tetrakis", "di", "tri"].contains(parts[0].lowercased()) { return true }
            // Lokant am Anfang: "4-Nitrostyrol", "1,4-Dioxan", "2-Amino-…"
            if parts[0].allSatisfy(\.isNumber) && parts.dropFirst().contains(where: { $0.count >= 3 }) { return true }
            if parts.allSatisfy({ elementSymbols.contains($0) || singleLetterElements.contains($0) }) && parts.contains(where: { elementSymbols.contains($0) }) { return true }
            return parts.contains { !$0.isEmpty && looksLikeSingleChemical($0) }
        }
        return looksLikeSingleChemical(word)
    }

    private static func looksLikeSingleChemical(_ word: String) -> Bool {
        let lower = word.lowercased()
        if Vocabulary.stopwords.contains(lower) { return false }
        if knownNames.contains(lower) || elementSymbols.contains(word) { return true }
        let letters = word.filter(\.isLetter)
        let digits = word.filter(\.isNumber)
        // Formeln: Buchstaben und Ziffern gemischt ("Et3N", "K2CO3", "H2O")
        if !letters.isEmpty && !digits.isEmpty && word.first?.isLetter == true { return true }
        // Großbuchstabe nach dem ersten Zeichen ("THF", "DMPU", "nBuLi", "CuI", "EtOAc")
        if word.dropFirst().contains(where: \.isUppercase) && letters.count >= 2 { return true }
        let stems = lower.count >= 8 && lower.hasSuffix("s") ? [lower, String(lower.dropLast())] : [lower]   // Genitiv
        if lower.count >= 5, stems.contains(where: { stem in suffixes.contains(where: { stem.hasSuffix($0) }) }) { return true }
        if lower.count >= 6, ["ene", "yne", "en", "in"].contains(where: { lower.hasSuffix($0) }), lower.hasPrefix("nitro") || lower.hasPrefix("chlor") || lower.hasPrefix("brom") || lower.hasPrefix("fluor") || lower.hasPrefix("iod") || lower.hasPrefix("methyl") || lower.hasPrefix("ethyl") || lower.hasPrefix("phenyl") || lower.hasPrefix("benz") { return true }
        if lower.count >= 4, lower.hasSuffix("yl") { return true }
        // Salze mit Kation am Wortanfang: "Natriumascorbat", "Kaliumcarbonat", "Ammoniumchlorid"
        if let prefix = cationPrefixes.first(where: { lower.hasPrefix($0) }), lower.count >= prefix.count + 3 { return true }
        return false
    }

    /// Zweite Namensteile, die für sich allein kein Name wären ("benzoic acid", "sodium salt", "acetic anhydride").
    private static let continuationWords: Set<String> = [
        "acid", "acids", "salt", "ester", "anhydride", "chloride", "bromide", "iodide", "fluoride", "oxide", "hydride",
        "hydroxide", "hydrate", "monohydrate", "dihydrate", "complex", "sieves", "alcohol", "aldehyde", "ketone", "amide",
        "amine", "ether", "acetate", "carbonate", "sulfate", "nitrate", "phosphate", "triflate", "säure", "salz",
    ]

    static func looksLikeContinuation(_ raw: String) -> Bool {
        if looksLikeChemical(raw) { return true }
        let lower = raw.lowercased()
        if continuationWords.contains(lower) { return true }
        if Vocabulary.stopwords.contains(lower) { return false }
        return lower.count >= 4 && lower.allSatisfy(\.isLetter) && continuationSuffixes.contains(where: { lower.hasSuffix($0) })
    }
}

nonisolated extension ChemicalData {
    var hasAnyQuantity: Bool { !equivalents.isEmpty || !amount.isEmpty || !volume.isEmpty || !mass.isEmpty }
}
