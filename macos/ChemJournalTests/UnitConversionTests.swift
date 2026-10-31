import Foundation
import Testing
@testable import ChemJournal

@Suite("Einheiten umrechnen (n, V, m)")
struct UnitConversionTests {
    @Test("Anzeige in mmol, µmol, mg, µl, l und kg")
    func display() {
        #expect(QuantityConversion.display("0.0015", in: QuantityKind.amount.unit("mmol"), kind: .amount) == "1.5")
        #expect(QuantityConversion.display("0.000115", in: QuantityKind.amount.unit("µmol"), kind: .amount) == "115")
        #expect(QuantityConversion.display("0.0123", in: QuantityKind.mass.unit("mg"), kind: .mass) == "12.3")
        #expect(QuantityConversion.display("1500", in: QuantityKind.mass.unit("kg"), kind: .mass) == "1.5")
        #expect(QuantityConversion.display("0.025", in: QuantityKind.volume.unit("µl"), kind: .volume) == "25")
        #expect(QuantityConversion.display("250", in: QuantityKind.volume.unit("l"), kind: .volume) == "0.25")
    }

    @Test("Basiseinheit und nicht lesbare Werte bleiben unverändert")
    func passthrough() {
        #expect(QuantityConversion.display("0.0015", in: QuantityKind.amount.unit("mol"), kind: .amount) == "0.0015")
        #expect(QuantityConversion.display("", in: QuantityKind.amount.unit("mmol"), kind: .amount) == "")
        #expect(QuantityConversion.display("ca. 2", in: QuantityKind.mass.unit("mg"), kind: .mass) == "ca. 2")
        #expect(QuantityConversion.toBase("abc", from: QuantityKind.mass.unit("mg")) == "abc")
        #expect(QuantityKind.mass.unit("unbekannt") == QuantityKind.mass.baseUnit)
    }

    @Test("Eingabe in der gewählten Einheit wird in mol/ml/g gespeichert, ohne Stellen zu verlieren")
    func toBase() {
        #expect(QuantityConversion.toBase("1.5", from: QuantityKind.amount.unit("mmol")) == "0.0015")
        #expect(QuantityConversion.toBase("12,34", from: QuantityKind.mass.unit("mg")) == "0.01234")
        #expect(QuantityConversion.toBase("25", from: QuantityKind.volume.unit("µl")) == "0.025")
        #expect(QuantityConversion.toBase("1.2", from: QuantityKind.mass.unit("kg")) == "1200")
        // Hin und zurück ergibt wieder die Eingabe
        let mmol = QuantityKind.amount.unit("mmol")
        #expect(QuantityConversion.display(QuantityConversion.toBase("0.75", from: mmol), in: mmol, kind: .amount) == "0.75")
    }
}

@Suite("Reinheit")
struct PurityTests {
    private func chem(M: String, purity: String) -> ChemicalData {
        var c = ChemicalData(); c.molarMass = M; c.purity = purity; return c
    }

    @Test("Werte aus dem Laborblatt (Carbazol 95 %, Pentafluorbenzonitril 98 %, NaH 60 %)")
    func labSheet() throws {
        // Carbazol 95 %, 6.5 mmol → 1144 mg
        let carbazole = try #require(chem(M: "167.21", purity: "95").massToWeigh(forAmount: 0.0065))
        #expect(Int((carbazole * 1000).rounded()) == 1144)
        // Pentafluorbenzonitril 98 %, 1 mmol → 197 mg, mit d = 1.53 g/ml → 129 µl
        let pfbn = try #require(chem(M: "193.08", purity: "98 %").massToWeigh(forAmount: 0.001))
        #expect(Int((pfbn * 1000).rounded()) == 197)
        #expect(Int((pfbn / 1.53 * 1000).rounded()) == 129)
        // NaH 60 % in Mineralöl, 9 mmol → 360 mg
        let nah = try #require(chem(M: "24", purity: "60%").massToWeigh(forAmount: 0.009))
        #expect(format3(nah) == "0.36")
        // Rückwärts: 360 mg NaH (60 %) enthalten 9 mmol NaH
        #expect(format4(try #require(chem(M: "24", purity: "60").pureAmount(inMass: 0.36))) == "0.009")
    }

    @Test("Leer, ungültig oder über 100 bedeutet 100 %")
    func defaults() {
        #expect(chem(M: "24", purity: "").purityFraction == 1)
        #expect(chem(M: "24", purity: "abc").purityFraction == 1)
        #expect(chem(M: "24", purity: "120").purityFraction == 1)
        #expect(chem(M: "24", purity: "0").purityFraction == 1)
        #expect(chem(M: "24", purity: "99,5").purityFraction == 0.995)
        #expect(chem(M: "", purity: "95").massToWeigh(forAmount: 1) == nil)
    }

    @Test("Ältere Dateien ohne Reinheit laden weiter; Reinheit wird gespeichert")
    func decoding() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"NaH","equivalents":"9","cas":"7646-69-7","molarMass":"24","density":"","amount":"0.009","volume":"","mass":"0.216"}"#
        let c = try JSONDecoder().decode(ChemicalData.self, from: Data(old.utf8))
        #expect(c.name == "NaH" && c.purity == "" && c.mass == "0.216")
        var withPurity = c; withPurity.purity = "60"
        let back = try JSONDecoder().decode(ChemicalData.self, from: JSONEncoder().encode(withPurity))
        #expect(back == withPurity)
    }
}
