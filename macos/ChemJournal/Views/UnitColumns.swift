import SwiftUI

/// Spaltenkopf wie "n (mol)": Ein Klick auf die Einheit zeigt die anderen Einheiten; die gewählte gilt für die
/// ganze Spalte.
struct UnitColumnHeader: View {
    let symbol: String
    let kind: QuantityKind
    @Binding var unitSymbol: String
    let minWidth: CGFloat

    var body: some View {
        let current = kind.unit(unitSymbol)
        HStack(spacing: 3) {
            Text(verbatim: symbol).fontWeight(.bold)
            Menu {
                ForEach(kind.units, id: \.symbol) { unit in
                    Button { unitSymbol = unit.symbol } label: {
                        if unit == current { Label(unit.symbol, systemImage: "checkmark") } else { Text(verbatim: unit.symbol) }
                    }
                }
            } label: {
                Text(verbatim: "(\(current.symbol))").fontWeight(.bold)
            }
            .menuStyle(.borderlessButton)
            // Der kleine Pfeil zeigt, dass die Einheit anklickbar ist
            .menuIndicator(.visible)
            .fixedSize()
            .help("Klicken, um die Einheit der Spalte zu wechseln")
        }
        .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
    }
}

/// Text, den der Nutzer gerade in ein umgerechnetes Feld tippt. Ohne diesen Puffer würde "1." beim Tippen
/// sofort zu "1" umformatiert.
struct UnitEditBuffer<Field: Hashable> {
    var field: Field?
    var text = ""
}

/// Bindung für ein Mengenfeld: zeigt den gespeicherten Wert (mol/ml/g) in der gewählten Einheit und
/// rechnet Eingaben zurück. In der Basiseinheit ist es die unveränderte Bindung.
func unitBinding<Field: Hashable>(_ base: Binding<String>, field: Field, unit: DisplayUnit, kind: QuantityKind,
                                  buffer: Binding<UnitEditBuffer<Field>>) -> Binding<String> {
    guard !unit.isBase else { return base }
    return Binding(
        get: {
            buffer.wrappedValue.field == field ? buffer.wrappedValue.text
                : QuantityConversion.display(base.wrappedValue, in: unit, kind: kind)
        },
        set: { newText in
            buffer.wrappedValue = UnitEditBuffer(field: field, text: newText)
            base.wrappedValue = QuantityConversion.toBase(newText, from: unit)
        })
}

/// Gewählte Anzeigeeinheiten einer Tabelle.
struct QuantityUnitSet: Equatable {
    var amount: DisplayUnit
    var volume: DisplayUnit
    var mass: DisplayUnit
    static let base = QuantityUnitSet(amount: QuantityKind.amount.baseUnit, volume: QuantityKind.volume.baseUnit,
                                      mass: QuantityKind.mass.baseUnit)
}
