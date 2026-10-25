import Foundation
import Testing
@testable import ChemJournal

@Suite("CAS-Suche (PubChem) – ohne Netz")
struct CASLookupTests {

    @Test("Gültige CAS-Nummern (Prüfziffer)", arguments: ["109-99-9", "7732-18-5", "584-08-7", "14221-01-3", "64-17-5", " 75-09-2 ", "109–99–9"])
    func valid(cas: String) {
        #expect(CASNumber.isValid(cas))
    }

    @Test("Ungültige oder unvollständige CAS-Nummern lösen keine Suche aus", arguments: ["109-99-8", "109-99-", "109-99", "1-23-4", "abc", "", "123-45-6789", "10999-9"])
    func invalid(cas: String) {
        #expect(!CASNumber.isValid(cas))
    }

    @Test("Dichte aus PubChem-Freitext", arguments: [
        // THF: ausdrückliche g/cm³-Angabe bei 25 °C gewinnt
        (["0.888 at 68 °F (USCG, 1999) - Less dense than water; will float", "0.8833 g/cu cm at 25 °C",
          "Saturated liquid density: 55.230 lb/cu ft; saturated vapor pressure: 2.913 lb/sq in", "Relative density (water = 1): 0.89", "0.89"], 0.8833),
        // Diisopropylamin: genauere Angabe bei gleicher Güte
        (["0.717 at 68 °F (USCG, 1999) - Less dense than water", "0.7169 @ 20 °C/4 °C", "Relative density (water = 1): 0.72", "0.72"], 0.7169),
        // Dichlormethan: "1.3255 20 °C/4 °C" statt "1.3"
        (["1.322 at 68 °F (USCG, 1999) - Denser than water", "1.3255 20 °C/4 °C", "Relative density (water = 1): 1.3 (20 °C)", "1.33"], 1.3255),
        // K2CO3, CuI: Feststoffe
        (["2.29 g/cu cm", "2.29 g/cm³", "2.29 @25 °C"], 2.29),
        (["5.67"], 5.67),
        // kg/m³ wird umgerechnet
        (["Density: 1049 kg/m3 at 20 °C"], 1.049),
    ])
    func density(entries: [String], expected: Double) {
        #expect(PubChemDensity.parse(entries) == expected)
    }

    @Test("Keine brauchbare Dichte: Spannen, lb-Angaben, Dampfdichte")
    func noDensity() {
        #expect(PubChemDensity.parse([]) == nil)
        #expect(PubChemDensity.parse(["1.040-1.047", "< 0.810"]) == nil)
        #expect(PubChemDensity.parse(["Bulk density: 6.1 lb/gal", "Vapor density: 2.5 (air = 1)"]) == nil)
    }

    @Test("PubChem-JSON: ID, Molmasse und Titel")
    func json() throws {
        let cids = Data(#"{"IdentifierList":{"CID":[8028,2724141]}}"#.utf8)
        #expect(PubChemJSON.firstCID(cids) == 8028)
        let props = Data(#"{"PropertyTable":{"Properties":[{"CID":8028,"MolecularWeight":"72.11","Title":"Tetrahydrofuran"}]}}"#.utf8)
        let p = try #require(PubChemJSON.properties(props))
        #expect(p.title == "Tetrahydrofuran" && p.molarMass == 72.11)
        let view = Data(#"{"Record":{"Section":[{"Information":[{"Value":{"StringWithMarkup":[{"String":"0.8833 g/cu cm at 25 °C"}]}}]}]}}"#.utf8)
        #expect(PubChemJSON.strings(view) == ["0.8833 g/cu cm at 25 °C"])
        #expect(PubChemJSON.firstCID(Data("{}".utf8)) == nil)
    }
}
