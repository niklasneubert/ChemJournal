import Foundation

/// Dezimaltrennzeichen des Taschenrechners (Einstellungen › Allgemein). Standard ist der Punkt.
nonisolated enum CalculatorSeparator: String, CaseIterable, Sendable {
    case point = "."
    case comma = ","

    static let defaultsKey = "calculator.decimalSeparator"
}

/// Rechenkern des kleinen Taschenrechners in der Symbolleiste.
///
/// Die Eingabe wird als Ausdruck gesammelt (intern immer mit „.“ als Dezimalzeichen), z. B. `12.5×(3+4)`, und mit
/// Punkt-vor-Strich ausgewertet. Unterstützt: + − × ÷, Klammern, Potenz (^, ²), Wurzel (√), Prozent (%),
/// Vorzeichenwechsel. Die Anzeige ersetzt den Punkt durch das eingestellte Trennzeichen.
nonisolated struct CalculatorEngine: Sendable {
    enum Key: Equatable, Sendable {
        case digit(Int), decimal
        case add, subtract, multiply, divide, power
        case openParen, closeParen
        case percent, square, squareRoot, negate
        case equals, clear, backspace
    }

    /// Aktueller Ausdruck (intern). Nach „=“ bleibt hier die gerechnete Aufgabe stehen, damit man sie ändern kann.
    private(set) var expression = ""
    /// Ergebnis der letzten Rechnung (nur solange `showsResult`).
    private(set) var result: Double?
    /// `true` direkt nach „=“: Eine Ziffer beginnt dann eine neue Rechnung, ein Rechenzeichen rechnet mit dem Ergebnis weiter.
    private(set) var showsResult = false
    /// `true`, wenn „=“ einen ungültigen Ausdruck (z. B. ÷ 0) ergeben hat.
    private(set) var hasError = false

    private static let operators: Set<Character> = ["+", "−", "×", "÷", "^"]

    /// Nur 0–9 (Character.isNumber gilt auch für „²“).
    static func isDigit(_ c: Character) -> Bool { ("0"..."9").contains(c) }

    init(expression: String = "") { self.expression = expression }

    // MARK: Eingabe

    /// Taste am Ende des Ausdrucks.
    mutating func press(_ key: Key) {
        if showsResult {
            if key == .equals { return }        // nochmal „=“: nichts ändern
            let previous = hasError ? nil : result.map(Self.resultText)
            showsResult = false; hasError = false; result = nil
            switch key {
            case .clear, .backspace: break      // ⌫ bearbeitet die gerechnete Aufgabe
            case .digit, .decimal, .openParen: expression = ""
            case .squareRoot:
                expression = previous.map { "√(" + $0 + ")" } ?? ""
                return
            default: expression = previous ?? ""   // Rechenzeichen: mit dem Ergebnis weiterrechnen
            }
        }
        switch key {
        case .digit(let d):
            if endsWithClosingTerm { expression += "×" }
            expression += String(d)
        case .decimal:
            if currentNumber.contains(".") { break }
            if endsWithClosingTerm { expression += "×" }
            expression += currentNumber.isEmpty ? "0." : "."
        case .add: appendOperator("+")
        case .subtract:
            // Am Anfang oder nach „(“ / einem Rechenzeichen ist − ein Vorzeichen
            if expression.isEmpty || expression.last == "(" || isOperator(expression.last) {
                if expression.last != "−" { expression += "−" }
            } else { appendOperator("−") }
        case .multiply: appendOperator("×")
        case .divide: appendOperator("÷")
        case .power: appendOperator("^")
        case .openParen:
            if endsWithClosingTerm || expression.last.map(Self.isDigit) == true || expression.last == "." { expression += "×" }
            expression += "("
        case .closeParen:
            if openParenCount > 0, let last = expression.last, last != "(", !isOperator(last) { expression += ")" }
        case .percent: appendPostfix("%")
        case .square: appendPostfix("²")
        case .squareRoot:
            if endsWithClosingTerm || expression.last.map(Self.isDigit) == true || expression.last == "." { expression += "×" }
            expression += "√("
        case .negate: negate()
        case .equals: evaluate()
        case .clear: expression = ""
        case .backspace:
            if expression.hasSuffix("√(") { expression.removeLast(2) }
            else if !expression.isEmpty { expression.removeLast() }
        }
    }

    /// Taste an einer Cursorposition (Zeichen-Offset im Ausdruck). Gibt die neue Cursorposition zurück.
    /// Am Ende verhält sich alles wie `press(_:)`; mitten im Ausdruck wird eingefügt bzw. vor dem Cursor gelöscht.
    @discardableResult
    mutating func press(_ key: Key, at cursor: Int) -> Int {
        let n = expression.count
        let c = min(max(cursor, 0), n)
        if c == n || key == .equals || key == .clear {
            press(key)
            return expression.count
        }
        // Mitten in der (auch gerechneten) Aufgabe: bearbeiten statt neu beginnen
        showsResult = false; hasError = false; result = nil
        var chars = Array(expression)
        if key == .backspace {
            guard c > 0 else { return 0 }
            let width = c >= 2 && chars[c - 2] == "√" && chars[c - 1] == "(" ? 2 : 1
            chars.removeSubrange((c - width)..<c)
            expression = String(chars)
            return c - width
        }
        var head = CalculatorEngine(expression: String(chars[..<c]))
        head.press(key)
        expression = head.expression + String(chars[c...])
        return head.expression.count
    }

    /// Ausdruck von Hand bearbeitet (Textfeld): übernehmen, Ergebnis-Modus verlassen.
    mutating func setExpression(_ text: String) {
        guard text != expression || showsResult else { return }
        expression = text
        showsResult = false; hasError = false; result = nil
    }

    /// Eingabe in die interne Schreibweise bringen: * → ×, / → ÷, - → −, Komma → Punkt.
    static func normalized(_ text: String) -> String {
        String(text.map { ch -> Character in
            switch ch {
            case "*", "x", "X": return "×"
            case "/", ":": return "÷"
            case "-": return "−"
            case ",": return "."
            default: return ch
            }
        })
    }

    /// Wert des aktuellen Ausdrucks (offene Klammern werden geschlossen), oder `nil`, solange er unvollständig ist.
    var currentValue: Double? {
        var text = expression
        while let last = text.last, isOperator(last) || last == "(" || last == "√" { text.removeLast() }
        guard !text.isEmpty else { return nil }
        text += String(repeating: ")", count: Self.openParens(in: text))
        return Self.evaluate(text)
    }

    // MARK: Anzeige

    /// Ausdruck für die Anzeige mit dem gewählten Dezimaltrennzeichen.
    func displayExpression(_ separator: CalculatorSeparator) -> String {
        separator == .point ? expression : expression.replacingOccurrences(of: ".", with: ",")
    }

    /// Zahl mit bis zu 10 gültigen Stellen, ohne Tausendertrennung (0.1 + 0.2 → „0.3“). Sehr große oder kleine Werte
    /// in Exponentialschreibweise („1.5e-9“).
    static func format(_ value: Double, separator: CalculatorSeparator) -> String {
        guard value.isFinite else { return "–" }
        var text = String(format: "%.10g", value == 0 ? 0 : value)   // keine „-0“
        if text.contains("e") {
            // „1.5e-09“ → „1.5e-9“, „2e+12“ → „2e12“
            let parts = text.split(separator: "e", maxSplits: 1).map(String.init)
            var exp = parts[1]
            let sign = exp.hasPrefix("-") ? "-" : ""
            exp = String(exp.drop(while: { $0 == "+" || $0 == "-" || $0 == "0" }))
            text = parts[0] + "e" + sign + (exp.isEmpty ? "0" : exp)
        }
        return separator == .point ? text : text.replacingOccurrences(of: ".", with: ",")
    }

    /// Zeichen aus der Tastatur. Punkt und Komma gelten beide als Dezimalzeichen.
    static func key(for character: Character) -> Key? {
        switch character {
        case "0"..."9": return .digit(Int(String(character))!)
        case ".", ",": return .decimal
        case "+": return .add
        case "-", "−": return .subtract
        case "*", "×", "x", "X": return .multiply
        case "/", "÷", ":": return .divide
        case "^": return .power
        case "(": return .openParen
        case ")": return .closeParen
        case "%": return .percent
        case "²": return .square
        case "=", "\r", "\n": return .equals
        case "c", "C": return .clear
        default: return nil
        }
    }

    // MARK: Intern

    private func isOperator(_ c: Character?) -> Bool { c.map { Self.operators.contains($0) } ?? false }

    /// Ausdruck endet mit „)“, „%“ oder „²“ – danach braucht eine Zahl ein ×.
    private var endsWithClosingTerm: Bool { [")", "%", "²"].contains(expression.last) }

    /// Die Zahl am Ende des Ausdrucks (Ziffern und Punkt).
    private var currentNumber: Substring { expression[numberStart...] }

    private var numberStart: String.Index {
        var i = expression.endIndex
        while i > expression.startIndex {
            let p = expression.index(before: i)
            guard Self.isDigit(expression[p]) || expression[p] == "." else { break }
            i = p
        }
        return i
    }

    private var openParenCount: Int { Self.openParens(in: expression) }

    private static func openParens(in text: String) -> Int {
        max(0, text.filter { $0 == "(" }.count - text.filter { $0 == ")" }.count)
    }

    private mutating func appendOperator(_ op: Character) {
        // Nach „=“ mit dem Ergebnis weiterrechnen; leerer Ausdruck: mit 0 beginnen
        if expression.isEmpty { expression = "0" }
        if expression.last == "(" || expression.hasSuffix("√(") { return }
        if expression.last == "." { expression.removeLast() }
        // Rechenzeichen ersetzen statt verdoppeln (auch ein Vorzeichen-Minus dahinter)
        while let last = expression.last, isOperator(last) { expression.removeLast() }
        if expression.isEmpty { expression = "0" }
        expression.append(op)
    }

    private mutating func appendPostfix(_ c: Character) {
        guard let last = expression.last, Self.isDigit(last) || last == ")" || last == "%" || last == "²" || last == "." else { return }
        if last == "." { expression.removeLast() }
        expression.append(c)
    }

    /// ± : Vorzeichen der letzten Zahl (bzw. Klammer) umschalten; nach „=“ das des Ergebnisses.
    private mutating func negate() {
        if expression.isEmpty { expression = "−"; return }
        if expression == "−" { expression = ""; return }
        var start = numberStart
        if start == expression.endIndex, expression.last == ")" {
            // ganze Klammer am Ende: passende „(“ suchen
            var depth = 0, i = expression.endIndex
            while i > expression.startIndex {
                i = expression.index(before: i)
                if expression[i] == ")" { depth += 1 } else if expression[i] == "(" { depth -= 1; if depth == 0 { break } }
            }
            start = i
            if start > expression.startIndex, expression[expression.index(before: start)] == "√" { start = expression.index(before: start) }
        }
        if start > expression.startIndex {
            let before = expression.index(before: start)
            let isUnaryMinus = expression[before] == "−" &&
                (before == expression.startIndex || isOperator(expression[expression.index(before: before)]) || expression[expression.index(before: before)] == "(")
            if isUnaryMinus { expression.remove(at: before); return }
        }
        expression.insert("−", at: start)
    }

    private mutating func evaluate() {
        var text = expression
        while let last = text.last, isOperator(last) || last == "(" || last == "√" || last == "." { text.removeLast() }
        guard !text.isEmpty else { return }
        text += String(repeating: ")", count: Self.openParens(in: text))
        expression = text
        showsResult = true
        if let value = Self.evaluate(text), value.isFinite { result = value } else { hasError = true }
    }

    /// Ergebnis als Zahl zum Weiterrechnen (intern, ohne Exponent): 0.1+0.2 → „0.3“.
    static func resultText(_ value: Double) -> String {
        let text = format(value, separator: .point)
        return text.contains("e") ? plainNumber(value) : text.replacingOccurrences(of: "-", with: "−")
    }

    /// Zahl ohne Exponent (für das Weiterrechnen mit sehr großen/kleinen Ergebnissen).
    private static func plainNumber(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.usesGroupingSeparator = false
        f.maximumSignificantDigits = 10
        f.usesSignificantDigits = true
        f.numberStyle = .decimal
        let s = f.string(from: NSNumber(value: abs(value))) ?? "0"
        return value < 0 ? "−" + s : s
    }

    // MARK: Auswertung (rekursiver Abstieg)

    /// Wertet einen vollständigen Ausdruck aus; `nil` bei Syntaxfehler, Division durch 0 oder Wurzel aus negativer Zahl.
    static func evaluate(_ text: String) -> Double? {
        var parser = Parser(chars: Array(text))
        guard let v = parser.parseSum(), parser.pos == parser.chars.count, v.isFinite else { return nil }
        return v
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0

        private var peek: Character? { pos < chars.count ? chars[pos] : nil }

        mutating func parseSum() -> Double? {
            guard var value = parseProduct() else { return nil }
            while let c = peek, c == "+" || c == "−" {
                pos += 1
                guard let rhs = parseProduct() else { return nil }
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseProduct() -> Double? {
            guard var value = parseUnary() else { return nil }
            while let c = peek, c == "×" || c == "÷" {
                pos += 1
                guard let rhs = parseUnary() else { return nil }
                if c == "÷" { guard rhs != 0 else { return nil }; value /= rhs } else { value *= rhs }
            }
            return value
        }

        /// Vorzeichen bindet schwächer als die Potenz: −2² = −4 (wie in der Mathematik).
        mutating func parseUnary() -> Double? {
            if peek == "−" { pos += 1; return parseUnary().map { -$0 } }
            if peek == "+" { pos += 1; return parseUnary() }
            return parsePower()
        }

        mutating func parsePower() -> Double? {
            guard let base = parsePostfix() else { return nil }
            if peek == "^" {
                pos += 1
                guard let exponent = parseUnary() else { return nil }   // rechtsassoziativ
                let v = pow(base, exponent)
                return v.isFinite ? v : nil
            }
            return base
        }

        mutating func parsePostfix() -> Double? {
            guard var value = parseAtom() else { return nil }
            while let c = peek, c == "%" || c == "²" {
                pos += 1
                value = c == "%" ? value / 100 : value * value
            }
            return value
        }

        mutating func parseAtom() -> Double? {
            guard let c = peek else { return nil }
            if c == "(" {
                pos += 1
                guard let v = parseSum(), peek == ")" else { return nil }
                pos += 1
                return v
            }
            if c == "√" {
                pos += 1
                guard let v = parseAtom(), v >= 0 else { return nil }
                return v.squareRoot()
            }
            var text = ""
            while let d = peek, CalculatorEngine.isDigit(d) || d == "." { text.append(d); pos += 1 }
            return Double(text)
        }
    }
}
