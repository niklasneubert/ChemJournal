import SwiftUI
import AppKit

// MARK: - Ansatzgrößen-Tabelle
struct ChemicalTableView: View {
    @Binding var chemicals: [ChemicalData]
    @Binding var showSmartExtract: Bool
    @State private var nameWidth: CGFloat = 160
    @State private var showScaleModal = false
    @State private var scaleFactorText = "1.0"
    // Anzeigeeinheiten der Mengenspalten (gelten für alle Ansatzgrößen-Tabellen; gespeichert wird in mol/ml/g)
    @AppStorage("unit.reagents.amount") private var amountUnit = "mol"
    @AppStorage("unit.reagents.volume") private var volumeUnit = "ml"
    @AppStorage("unit.reagents.mass") private var massUnit = "g"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ansatzgrößen").font(.headline)
                Spacer()
                Button(action: { scaleFactorText = "1.0"; showScaleModal = true }) {
                    Label("Skalieren", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline).foregroundColor(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1)).cornerRadius(6)
                }.buttonStyle(.plain)
                Button(action: { showSmartExtract = true }) {
                    Label("Smart Extract", systemImage: "wand.and.stars")
                        .font(.subheadline).foregroundColor(.purple)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1)).cornerRadius(6)
                }.buttonStyle(.plain)
            }.padding([.top, .leading, .trailing], 12).padding(.bottom, 8)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    HStack(spacing: 0) {
                        Text("Name").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                        ColumnResizeHandle(width: $nameWidth)
                    }.frame(width: nameWidth)
                    // Gleiche Mindestbreiten wie die Felder darunter – sonst rücken die Köpfe einer leeren Tabelle zusammen
                    columnHeader("eq", minWidth: 40); columnHeader("CAS", minWidth: 70); columnHeader("M (g/mol)", minWidth: 60)
                    columnHeader("d (g/cm3)", minWidth: 60)
                    columnHeader("Reinheit (%)", minWidth: 50)
                        .help("Gehalt des Reagenzes, z. B. 95 oder 60 (NaH in Mineralöl). Leer = 100 %. n bleibt die Stoffmenge des reinen Stoffes, m und V sind die abzumessende Menge.")
                    UnitColumnHeader(symbol: "n", kind: .amount, unitSymbol: $amountUnit, minWidth: 60)
                    UnitColumnHeader(symbol: "V", kind: .volume, unitSymbol: $volumeUnit, minWidth: 60)
                    UnitColumnHeader(symbol: "m", kind: .mass, unitSymbol: $massUnit, minWidth: 60)
                    Text("").frame(width: 16)
                }.padding(.bottom, 4)
                Divider()
                ForEach($chemicals) { $chem in
                    ChemicalRowView(chemical: $chem, allChemicals: chemicals, nameWidth: $nameWidth,
                                    units: .init(amount: QuantityKind.amount.unit(amountUnit), volume: QuantityKind.volume.unit(volumeUnit),
                                                 mass: QuantityKind.mass.unit(massUnit))) { triggerGlobalUpdate() } onDelete: { chemicals.removeAll { $0.id == chem.id } }
                    Divider()
                }
            }.padding(.horizontal, 12)
            Button(action: { chemicals.append(ChemicalData()) }) { HStack { Image(systemName: "plus"); Text("Chemikalie hinzufügen") }.font(.subheadline).foregroundColor(.green).padding(12) }.buttonStyle(.plain)
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.5)).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .onChange(of: chemicals.first?.amount) { _, _ in triggerGlobalUpdate() }
        .onChange(of: chemicals.first?.equivalents) { _, _ in triggerGlobalUpdate() }
        .sheet(isPresented: $showScaleModal) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ansatz skalieren").font(.title2.bold())
                Text("Alle Mengen (n, m, V) werden mit dem Faktor multipliziert.").font(.subheadline).foregroundColor(.secondary)
                HStack { Text("Faktor:").font(.headline); TextField("z.B. 0.5", text: $scaleFactorText).textFieldStyle(.roundedBorder).frame(width: 100) }
                HStack { Spacer(); Button("Abbrechen") { showScaleModal = false }; Button("Skalieren") { applyScale(); showScaleModal = false }.buttonStyle(.borderedProminent).tint(.orange) }
            }.padding(24).frame(width: 380)
        }
        .sheet(isPresented: $showSmartExtract) {
            SmartExtractSheet { rows in chemicals.append(contentsOf: rows) }
        }
    }

    private func columnHeader(_ title: LocalizedStringKey, minWidth: CGFloat) -> some View {
        Text(title).fontWeight(.bold).frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
    }

    func applyScale() {
        guard let factor = parseDecimal(scaleFactorText), factor > 0 else { return }
        for i in chemicals.indices {
            if let n = parseDecimal(chemicals[i].amount) { chemicals[i].amount = format4(n * factor) }
            if let m = parseDecimal(chemicals[i].mass) { chemicals[i].mass = format3(m * factor) }
            if let v = parseDecimal(chemicals[i].volume) { chemicals[i].volume = format3(v * factor) }
        }
    }

    /// Rechnet alle Zeilen über ihre Äquivalente aus der ersten Zeile (Leit-Reaktand) neu.
    func triggerGlobalUpdate() {
        guard chemicals.count > 1 else { return }
        let refN = parseDecimal(chemicals[0].amount) ?? 0.0
        let refEq = parseDecimal(chemicals[0].equivalents) ?? 1.0
        let baseAmount = refN / (refEq > 0 ? refEq : 1.0)
        guard baseAmount > 0 else { return }
        for i in 1..<chemicals.count {
            let eq = parseDecimal(chemicals[i].equivalents) ?? 0.0
            if eq > 0 {
                let newN = eq * baseAmount; chemicals[i].amount = format4(newN)
                // Reinheit: für n mol reinen Stoff muss mehr abgewogen werden (m = n · M / Reinheit)
                if let m = chemicals[i].massToWeigh(forAmount: newN) { chemicals[i].mass = format3(m); let d = parseDecimal(chemicals[i].density) ?? 0.0; if d > 0 { chemicals[i].volume = format3(m / d) } }
            }
        }
    }
}

// MARK: - Smart-Extract-Dialog
struct SmartExtractSheet: View {
    var onExtracted: ([ChemicalData]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var isExtracting = false
    @State private var showNothingFound = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Smart Extract", systemImage: "wand.and.stars").font(.title2.bold())
            Text("Füge hier die Versuchsvorschrift aus einem Paper oder einer SI ein. Die Auswertung läuft komplett auf deinem Mac.").font(.subheadline).foregroundColor(.secondary)
            TextEditor(text: $inputText).font(.body).frame(minHeight: 150).padding(4).background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            HStack {
                if isExtracting { ProgressView().controlSize(.small); Text("Analysiere…").font(.caption).foregroundColor(.secondary) }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Extrahieren") { extract() }
                    .buttonStyle(.borderedProminent).tint(.purple)
                    .disabled(isExtracting || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 500, height: 350)
        .task { await SmartExtractService.shared.warmUp() }
        .alert("Keine Chemikalien gefunden", isPresented: $showNothingFound) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Im Text wurden keine Mengenangaben oder Chemikaliennamen erkannt.")
        }
    }

    private func extract() {
        let text = inputText
        isExtracting = true
        Task {
            // Modell und Parser laufen im Hintergrund (Actor); dieser Task kehrt auf den MainActor zurück
            let rows = await SmartExtractService.shared.extract(from: text)
            isExtracting = false
            if rows.isEmpty { showNothingFound = true; return }
            onExtracted(rows)
            dismiss()
        }
    }
}

// MARK: - Tabellenzeile
struct ChemicalRowView: View {
    @Binding var chemical: ChemicalData; var allChemicals: [ChemicalData]; @Binding var nameWidth: CGFloat; var units = QuantityUnitSet.base; var onUpdate: () -> Void; var onDelete: () -> Void
    enum Field { case name, eq, cas, molarMass, density, purity, amount, volume, mass }
    @FocusState private var focusedField: Field?; @State private var tempName: String = ""
    @State private var unitEdit = UnitEditBuffer<Field>()
    @State private var casStatus: CASLookupStatus = .idle
    var body: some View {
        GridRow {
            TextField("Name", text: $tempName).focused($focusedField, equals: .name).textFieldStyle(.roundedBorder).frame(width: max(40, nameWidth - 8))
                .onAppear { tempName = chemical.name }.onChange(of: chemical.name) { _, newV in if focusedField != .name { tempName = newV } }.onSubmit { commitName() }.onChange(of: focusedField) { oldF, newF in if oldF == .name && newF != .name { commitName() } }
            TextField("eq", text: $chemical.equivalents).focused($focusedField, equals: .eq).textFieldStyle(.roundedBorder).frame(minWidth: 40).onChange(of: chemical.equivalents) { _, _ in calculate(source: .eq) }
            TextField("CAS", text: $chemical.cas).focused($focusedField, equals: .cas).textFieldStyle(.roundedBorder).frame(minWidth: 70)
                .overlay(alignment: .trailing) { CASStatusIcon(status: casStatus) }
                .onChange(of: chemical.cas) { _, newValue in casChanged(newValue) }
            TextField("M", text: $chemical.molarMass).focused($focusedField, equals: .molarMass).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: chemical.molarMass) { _, _ in calculate(source: .molarMass) }
            TextField("d", text: $chemical.density).focused($focusedField, equals: .density).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: chemical.density) { _, _ in calculate(source: .density) }
                .onChange(of: focusedField) { old, new in if (old == .molarMass || old == .density) && new != old { saveCASValues() } }
            TextField("100", text: $chemical.purity).focused($focusedField, equals: .purity).textFieldStyle(.roundedBorder).frame(minWidth: 50).onChange(of: chemical.purity) { _, _ in calculate(source: .purity) }
            TextField("n", text: unitBinding($chemical.amount, field: .amount, unit: units.amount, kind: .amount, buffer: $unitEdit)).focused($focusedField, equals: .amount).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: chemical.amount) { _, _ in calculate(source: .amount) }
            TextField("V", text: unitBinding($chemical.volume, field: .volume, unit: units.volume, kind: .volume, buffer: $unitEdit)).focused($focusedField, equals: .volume).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: chemical.volume) { _, _ in calculate(source: .volume) }
            TextField("m", text: unitBinding($chemical.mass, field: .mass, unit: units.mass, kind: .mass, buffer: $unitEdit)).focused($focusedField, equals: .mass).textFieldStyle(.roundedBorder).frame(minWidth: 60).onChange(of: chemical.mass) { _, _ in calculate(source: .mass) }
            Button(action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain)
        }.padding(.vertical, 4)
        // Beim Verlassen des Feldes oder Wechsel der Einheit wieder den umgerechneten Wert zeigen
        .onChange(of: focusedField) { _, _ in unitEdit = UnitEditBuffer() }
        .onChange(of: units) { _, _ in unitEdit = UnitEditBuffer() }
    }

    private func commitName() { let f = applySmartFormatting(to: tempName); chemical.name = f; tempName = f }

    /// CAS geändert: gespeicherte Werte oder PubChem-Suche im Hintergrund, danach neu rechnen.
    private func casChanged(_ cas: String) {
        let binding = $chemical
        CASAutofill.casChanged(cas, current: { (binding.wrappedValue.cas, Self.values(binding.wrappedValue)) }, status: $casStatus) { molarMass, density in
            if let molarMass, binding.wrappedValue.molarMass != molarMass { binding.wrappedValue.molarMass = molarMass; calculate(source: .molarMass, forceCalc: true) }
            if let density, binding.wrappedValue.density != density { binding.wrappedValue.density = density; calculate(source: .density, forceCalc: true) }
        }
    }

    /// Von Hand geänderte Molmasse/Dichte in der CAS-Datenbank merken (beim Verlassen des Feldes).
    private func saveCASValues() {
        guard CASNumber.isValid(chemical.cas) else { return }
        CASAutofill.saveUserValues(cas: chemical.cas, values: Self.values(chemical))
        if let entry = CASDatabase.shared.entry(for: chemical.cas) {
            casStatus = .saved(String(localized: "Als eigene Eingabe gespeichert: M \(entry.molarMass.isEmpty ? "–" : entry.molarMass) g/mol, d \(entry.density.isEmpty ? "–" : entry.density) g/cm³"))
        }
    }

    private static func values(_ row: ChemicalData) -> CASAutofill.RowValues {
        CASAutofill.RowValues(name: row.name, molarMass: row.molarMass, density: row.density)
    }

    /// Rechnet die Zeile nach einer Eingabe neu. n ist die Stoffmenge des reinen Stoffes (daraus die Äquivalente),
    /// m und V sind die abzumessende Menge des Reagenzes: m = n · M / Reinheit, V = m / d
    /// (wie im Laborblatt: NaH 60 % in Mineralöl, 9 mmol → 9 · 24 / 0.6 = 360 mg).
    private func calculate(source: Field, forceCalc: Bool = false) {
        guard focusedField == source || forceCalc else { return }
        let M = parseDecimal(chemical.molarMass) ?? 0.0; let d = parseDecimal(chemical.density) ?? 0.0
        let isRef = (allChemicals.first?.id == chemical.id)
        let refEq = parseDecimal(allChemicals.first?.equivalents ?? "") ?? 1.0
        let baseAmount = (parseDecimal(allChemicals.first?.amount ?? "") ?? 0.0) / (refEq > 0 ? refEq : 1.0)
        let n = parseDecimal(chemical.amount); let m = parseDecimal(chemical.mass); let V = parseDecimal(chemical.volume); let eq = parseDecimal(chemical.equivalents)
        var trigGlobal = false
        /// Aus der Stoffmenge: Masse und Volumen des Reagenzes
        func setMassAndVolume(fromAmount n: Double) {
            guard let mass = chemical.massToWeigh(forAmount: n) else { return }
            chemical.mass = format3(mass)
            if d > 0 { chemical.volume = format3(mass / d) }
        }
        /// Aus der abgewogenen Masse: Stoffmenge (und Äquivalente) des reinen Stoffes
        func setAmount(fromMass mass: Double) {
            guard let calcN = chemical.pureAmount(inMass: mass) else { return }
            chemical.amount = format4(calcN)
            if !isRef && baseAmount > 0 { chemical.equivalents = format4(calcN / baseAmount) } else if isRef { trigGlobal = true }
        }
        switch source {
        case .eq: if !isRef, let eq = eq, baseAmount > 0 { let calcN = eq * baseAmount; chemical.amount = format4(calcN); setMassAndVolume(fromAmount: calcN) } else if isRef { trigGlobal = true }
        case .amount: if let n = n { if !isRef && baseAmount > 0 { chemical.equivalents = format4(n / baseAmount) } else if isRef { trigGlobal = true }; setMassAndVolume(fromAmount: n) }
        case .mass: if let m = m { setAmount(fromMass: m); if d > 0 { chemical.volume = format3(m / d) } }
        case .volume: if let V = V, d > 0 { let calcM = V * d; chemical.mass = format3(calcM); setAmount(fromMass: calcM) }
        case .molarMass: if let m = m, M > 0 { setAmount(fromMass: m); if d > 0 { chemical.volume = format3(m / d) } } else if let n = n { setMassAndVolume(fromAmount: n) }
        case .density: if let m = m, d > 0 { chemical.volume = format3(m / d) }
        // Reinheit geändert: die benötigte Stoffmenge bleibt, abzuwiegende Menge passt sich an
        case .purity: if let n = n { setMassAndVolume(fromAmount: n) } else if let m = m { setAmount(fromMass: m) }
        default: break
        }
        if trigGlobal { DispatchQueue.main.async { onUpdate() } }
    }
}
