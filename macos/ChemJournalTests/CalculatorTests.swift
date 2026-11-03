import Foundation
import Testing
@testable import ChemJournal

@Suite("Taschenrechner")
struct CalculatorTests {
    /// Tippt eine Folge wie auf der Tastatur ein ("12.5*3=").
    private func typed(_ keys: String) -> CalculatorEngine {
        var c = CalculatorEngine()
        for ch in keys { if let k = CalculatorEngine.key(for: ch) { c.press(k) } }
        return c
    }

    @Test("Punkt vor Strich, Klammern, Potenz, Wurzel, Prozent")
    func evaluation() {
        #expect(CalculatorEngine.evaluate("2+3×4") == 14)
        #expect(CalculatorEngine.evaluate("(2+3)×4") == 20)
        #expect(CalculatorEngine.evaluate("10÷4") == 2.5)
        #expect(CalculatorEngine.evaluate("2^3^2") == 512)
        #expect(CalculatorEngine.evaluate("−2²") == -4)
        #expect(CalculatorEngine.evaluate("√(16)+1") == 5)
        #expect(CalculatorEngine.evaluate("50%×80") == 40)
        #expect(CalculatorEngine.evaluate("3−−2") == 5)
        #expect(CalculatorEngine.evaluate("1÷0") == nil)
        #expect(CalculatorEngine.evaluate("√(−4)") == nil)
        #expect(CalculatorEngine.evaluate("2+") == nil)
    }

    @Test("Eingabe wie auf der Tastatur; nach „=“ bleibt die Aufgabe stehen")
    func typing() {
        var c = typed("12.5*3=")
        #expect(c.expression == "12.5×3")
        #expect(c.result == 37.5 && c.showsResult)
        // Rechenzeichen nach „=“ rechnet mit dem Ergebnis weiter, eine Ziffer beginnt neu
        c.press(.add); c.press(.digit(2))
        #expect(c.expression == "37.5+2")
        c.press(.equals)
        #expect(c.result == 39.5)
        c.press(.digit(7))
        #expect(c.expression == "7")
        // doppelte Rechenzeichen werden ersetzt, Komma gilt als Dezimalzeichen
        #expect(typed("8+*2=").result == 16)
        #expect(typed("1,5+1,5=").result == 3)
        #expect(typed("0.1+0.2+=").expression == "0.1+0.2")
        // offene Klammern werden bei „=“ geschlossen; 2( wird zu 2×(
        #expect(typed("2(3+4=").expression == "2×(3+4)")
        #expect(typed("2(3+4=").result == 14)
        // Zwischenergebnis während der Eingabe
        #expect(typed("6*7+").currentValue == 42)
        #expect(typed("6/0=").hasError)
        #expect(typed("6/0=7").expression == "7")
        // weiterrechnen mit einem Ergebnis ohne Rundungsfehler
        var d = typed("0.1+0.2=")
        d.press(.multiply); d.press(.digit(3))
        #expect(d.expression == "0.3×3")
    }

    @Test("Aufgabe nach „=“ bearbeiten: Cursor, Einfügen, Löschen")
    func cursorEditing() {
        var c = typed("12+3=")
        // ⌫ am Ende bearbeitet die gerechnete Aufgabe statt sie zu löschen
        var e = c
        e.press(.backspace)
        #expect(e.expression == "12+" && !e.showsResult)
        // Cursor hinter „12“: Ziffer einfügen → 125+3
        var pos = c.press(.digit(5), at: 2)
        #expect(c.expression == "125+3" && pos == 3 && !c.showsResult)
        #expect(c.currentValue == 128)
        // ⌫ vor dem Cursor
        pos = c.press(.backspace, at: 1)
        #expect(c.expression == "25+3" && pos == 0)
        // Rechenzeichen in der Mitte ersetzt kein Zeichen dahinter
        pos = c.press(.multiply, at: 2)
        #expect(c.expression == "25×+3")
        // Wurzel-Klammer wird zusammen gelöscht
        var w = CalculatorEngine(expression: "2×√(9)")
        pos = w.press(.backspace, at: 4)
        #expect(w.expression == "2×9)" && pos == 2)
        // Eingabe von Hand
        var h = typed("1+1=")
        h.setExpression(CalculatorEngine.normalized("3*4-1"))
        #expect(h.expression == "3×4−1" && h.currentValue == 11 && !h.showsResult)
        #expect(CalculatorEngine.normalized("2,5/5") == "2.5÷5")
    }

    @Test("Vorzeichen, Löschen, Rücktaste")
    func editing() {
        var c = typed("5+3")
        c.press(.negate)
        #expect(c.expression == "5+−3")
        c.press(.negate)
        #expect(c.expression == "5+3")
        c.press(.backspace)
        #expect(c.expression == "5+")
        c.press(.clear)
        #expect(c.expression.isEmpty)
        var r = typed("4=")
        r.press(.negate)
        #expect(r.expression == "−4")
        var w = typed("16=")
        w.press(.squareRoot)
        #expect(w.expression == "√(16)")
        #expect(w.currentValue == 4)
    }

    @Test("Anzeige mit Punkt oder Komma")
    func display() {
        #expect(CalculatorEngine.format(1234.5, separator: .point) == "1234.5")
        #expect(CalculatorEngine.format(1234.5, separator: .comma) == "1234,5")
        #expect(CalculatorEngine.format(0.1 + 0.2, separator: .point) == "0.3")
        #expect(CalculatorEngine.format(1.5e-9, separator: .comma) == "1,5e-9")
        #expect(CalculatorEngine.format(2e12, separator: .point) == "2e12")
        #expect(CalculatorEngine.format(-0.0, separator: .point) == "0")
        #expect(typed("2.5*2").displayExpression(.comma) == "2,5×2")
    }
}
