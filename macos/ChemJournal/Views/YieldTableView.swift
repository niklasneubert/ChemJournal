import SwiftUI
import AppKit

struct YieldTableView: View {
    @Binding var yields: [YieldData]; @Binding var allChemicals: [ChemicalData]; @State private var nameWidth: CGFloat = 160
    // Anzeigeeinheiten der Mengenspalten (gelten für alle Ausbeute-Tabellen; gespeichert wird in mol/ml/g)
    @AppStorage("unit.yield.amount") private var amountUnit = "mol"
    @AppStorage("unit.yield.volume") private var volumeUnit = "ml"
    @AppStorage("unit.yield.mass") private var massUnit = "g"
    private func header(_ title: LocalizedStringKey, minWidth: CGFloat, maxWidth: CGFloat = .infinity) -> some View {
        Text(title).fontWeight(.bold).frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ausbeute (Produkt)").font(.headline).padding([.top, .leading, .trailing], 12).padding(.bottom, 8)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    HStack(spacing: 0) { Text("Produktname").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading); ColumnResizeHandle(width: $nameWidth) }.frame(width: nameWidth)
                    // Gleiche Mindestbreiten wie die Felder darunter – sonst rücken die Köpfe einer leeren Tabelle zusammen
                    header("CAS", minWidth: 70); header("Bezug", minWidth: 90, maxWidth: 140); header("M (g/mol)", minWidth: 60); header("d (g/cm3)", minWidth: 60)
                    UnitColumnHeader(symbol: "n", kind: .amount, unitSymbol: $amountUnit, minWidth: 60)
                    UnitColumnHeader(symbol: "V", kind: .volume, unitSymbol: $volumeUnit, minWidth: 60)
                    UnitColumnHeader(symbol: "m", kind: .mass, unitSymbol: $massUnit, minWidth: 60)
                    header("m theor.", minWidth: 60).foregroundColor(.secondary)
                    header("Ausbeute", minWidth: 60).foregroundColor(.green); Text("").frame(width: 16)
                }.padding(.bottom, 4); Divider()
                ForEach($yields) { $yieldItem in YieldRowView(yieldData: $yieldItem, allChemicals: allChemicals, nameWidth: $nameWidth,
                                 units: .init(amount: QuantityKind.amount.unit(amountUnit), volume: QuantityKind.volume.unit(volumeUnit),
                                              mass: QuantityKind.mass.unit(massUnit))) { yields.removeAll { $0.id == yieldItem.id } }; Divider() }
            }.padding(.horizontal, 12)
            Button(action: { yields.append(YieldData()) }) { HStack { Image(systemName: "plus"); Text("Produkt hinzufügen") }.font(.subheadline).foregroundColor(.green).padding(12) }.buttonStyle(.plain)
        }.background(Color(NSColor.textBackgroundColor).opacity(0.5)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
}

struct YieldRowView: View {
    @Binding var yieldData: YieldData; var allChemicals: [ChemicalData]; @Binding var nameWidth: CGFloat; var units = QuantityUnitSet.base; var onDelete: () -> Void
    enum Field { case name, cas, molarMass, density, amount, volume, mass }
    @FocusState private var focusedField: Field?; @State private var tempName: String = ""
    @State private var unitEdit = UnitEditBuffer<Field>()
    @State private var casStatus: CASLookupStatus = .idle

    private var referenceAmount: Double? {
        guard let refID = yieldData.referenceChemicalID, let refChem = allChemicals.first(where: { $0.id == refID }) else { return nil }
        return parseDecimal(refChem.amount)
    }

    func currentYield() -> String {
        guard let refN = referenceAmount, refN > 0, let myN = parseDecimal(yieldData.amount), myN > 0 else { return "–" }
        return String(format: "%.1f %%", (myN / refN) * 100)
    }

    func theoreticalMass() -> String {
        guard let refN = referenceAmount, let M = parseDecimal(yieldData.molarMass) else { return "–" }
        return QuantityConversion.format(refN * M / units.mass.factor, kind: .mass) + " " + units.mass.symbol
    }

    var body: some View {
        GridRow {
            TextField("Produktname", text: $tempName).focused($focusedField, equals: .name).textFieldStyle(.roundedBorder).frame(width: max(40, nameWidth - 8)).onAppear { tempName = yieldData.name }.onChange(of: yieldData.name) { _, newV in if focusedField != .name { tempName = newV } }.onSubmit { commitName() }.onChange(of: focusedField) { oldF, newF in if oldF == .name && newF != .name { commitName() } }
            TextField("CAS", text: $yieldData.cas).focused($focusedField, equals: .cas).textFieldStyle(.roundedBorder).frame(minWidth: 70)
                .overlay(alignment: .trailing) { CASStatusIcon(status: casStatus) }
                .onChange(of: yieldData.cas) { _, newValue in casChanged(newValue) }
            Picker("", selection: $yieldData.referenceChemicalID) { Text("Wählen...").tag(UUID?.none); ForEach(allChemicals, id: \.id) { chem in if !chem.name.isEmpty { Text(chem.name).tag(UUID?.some(chem.id)) } } }.labelsHidden().frame(minWidth: 90, maxWidth: 140)
            TextField("M", text: $yieldData.molarMass).focused($focusedField, equals: .molarMass).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: yieldData.molarMass) { _, _ in calculate(source: .molarMass) }
            TextField("d", text: $yieldData.density).focused($focusedField, equals: .density).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: yieldData.density) { _, _ in calculate(source: .density) }
                .onChange(of: focusedField) { old, new in if (old == .molarMass || old == .density) && new != old { saveCASValues() } }
            TextField("n", text: unitBinding($yieldData.amount, field: .amount, unit: units.amount, kind: .amount, buffer: $unitEdit)).focused($focusedField, equals: .amount).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: yieldData.amount) { _, _ in calculate(source: .amount) }
            TextField("V", text: unitBinding($yieldData.volume, field: .volume, unit: units.volume, kind: .volume, buffer: $unitEdit)).focused($focusedField, equals: .volume).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: yieldData.volume) { _, _ in calculate(source: .volume) }
            TextField("m", text: unitBinding($yieldData.mass, field: .mass, unit: units.mass, kind: .mass, buffer: $unitEdit)).focused($focusedField, equals: .mass).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: yieldData.mass) { _, _ in calculate(source: .mass) }
            Text(theoreticalMass()).font(.caption).foregroundColor(.secondary).frame(minWidth: 60)
            Text(currentYield()).fontWeight(.bold).foregroundColor(.green).frame(minWidth: 60)
            Button(action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain)
        }.padding(.vertical, 4)
        // Beim Verlassen des Feldes oder Wechsel der Einheit wieder den umgerechneten Wert zeigen
        .onChange(of: focusedField) { _, _ in unitEdit = UnitEditBuffer() }
        .onChange(of: units) { _, _ in unitEdit = UnitEditBuffer() }
    }

    private func commitName() { let f = applySmartFormatting(to: tempName); yieldData.name = f; tempName = f }

    /// CAS geändert: gespeicherte Werte oder PubChem-Suche im Hintergrund, danach neu rechnen.
    private func casChanged(_ cas: String) {
        let binding = $yieldData
        CASAutofill.casChanged(cas, current: { (binding.wrappedValue.cas, Self.values(binding.wrappedValue)) }, status: $casStatus) { molarMass, density in
            if let molarMass, binding.wrappedValue.molarMass != molarMass { binding.wrappedValue.molarMass = molarMass; calculate(source: .molarMass, forceCalc: true) }
            if let density, binding.wrappedValue.density != density { binding.wrappedValue.density = density; calculate(source: .density, forceCalc: true) }
        }
    }

    /// Von Hand geänderte Molmasse/Dichte in der CAS-Datenbank merken (beim Verlassen des Feldes).
    private func saveCASValues() {
        guard CASNumber.isValid(yieldData.cas) else { return }
        CASAutofill.saveUserValues(cas: yieldData.cas, values: Self.values(yieldData))
        if let entry = CASDatabase.shared.entry(for: yieldData.cas) {
            casStatus = .saved(String(localized: "Als eigene Eingabe gespeichert: M \(entry.molarMass.isEmpty ? "–" : entry.molarMass) g/mol, d \(entry.density.isEmpty ? "–" : entry.density) g/cm³"))
        }
    }

    private static func values(_ row: YieldData) -> CASAutofill.RowValues {
        CASAutofill.RowValues(name: row.name, molarMass: row.molarMass, density: row.density)
    }

    private func calculate(source: Field, forceCalc: Bool = false) {
        guard focusedField == source || forceCalc else { return }
        let M = parseDecimal(yieldData.molarMass) ?? 0.0; let d = parseDecimal(yieldData.density) ?? 0.0
        let n = parseDecimal(yieldData.amount); let m = parseDecimal(yieldData.mass); let V = parseDecimal(yieldData.volume)
        switch source {
        case .amount: if let n = n { if M > 0 { yieldData.mass = format3(n * M); if d > 0 { yieldData.volume = format3((n * M) / d) } } }
        case .mass: if let m = m, M > 0 { let calcN = m / M; yieldData.amount = format4(calcN); if d > 0 { yieldData.volume = format3(m / d) } }
        case .volume: if let V = V, d > 0 { let calcM = V * d; yieldData.mass = format3(calcM); if M > 0 { yieldData.amount = format4(calcM / M) } }
        case .molarMass: if let m = m, M > 0 { let calcN = m / M; yieldData.amount = format4(calcN); if d > 0 { yieldData.volume = format3(m / d) } } else if let n = n, M > 0 { yieldData.mass = format3(n * M); if d > 0 { yieldData.volume = format3((n * M) / d) } }
        case .density: if let m = m, d > 0 { yieldData.volume = format3(m / d) }
        default: break
        }
    }
}

/// Ziehgriff für die Breite der Namensspalte. Merkt sich, ob der Cursor gesetzt wurde,
/// damit `NSCursor.pop()` nicht öfter aufgerufen wird als `push()`.
struct ColumnResizeHandle: View {
    @Binding var width: CGFloat
    @State private var cursorPushed = false
    @State private var startWidth: CGFloat?

    var body: some View {
        Divider().frame(width: 8).contentShape(Rectangle())
            .onHover { inside in
                if inside && !cursorPushed { NSCursor.resizeLeftRight.push(); cursorPushed = true }
                else if !inside && cursorPushed { NSCursor.pop(); cursorPushed = false }
            }
            .gesture(DragGesture()
                .onChanged { v in
                    let base = startWidth ?? width
                    if startWidth == nil { startWidth = width }
                    width = max(80, base + v.translation.width)
                }
                .onEnded { _ in startWidth = nil })
    }
}
