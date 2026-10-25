import Foundation

/// Sucht Molmasse und Dichte zu einer CAS-Nummer in PubChem (frei, ohne API-Schlüssel).
///
/// Ablauf:
/// 1. CAS-Nummer prüfen (Format und Prüfziffer) – ungültige Eingaben lösen keine Anfrage aus.
/// 2. `compound/name/<CAS>/cids` → PubChem-ID. Die Synonymsuche ist zuverlässiger als der CAS-Querverweis
///    (`xref/RN`), der z. B. für CuI als erstes "2-Phenylcyclohexanol" liefert.
/// 3. `property/MolecularWeight,Title` → Molmasse in g/mol.
/// 4. `pug_view … heading=Density` → Dichteangaben als Text; `PubChemDensity.parse` wählt einen Wert in g/cm³.
///
/// An PubChem wird nur die CAS-Nummer gesendet.
actor CASLookupService {
    static let shared = CASLookupService()

    struct Result: Sendable, Equatable {
        let title: String
        let molarMass: Double
        /// g/cm³ (= g/ml). `nil`, wenn PubChem keine brauchbare Angabe hat (z. B. NaH).
        let density: Double?
    }

    enum LookupError: LocalizedError {
        case invalidCAS, notFound, network(String)
        var errorDescription: String? {
            switch self {
            case .invalidCAS: "Ungültige CAS-Nummer (Prüfziffer stimmt nicht)."
            case .notFound: "In PubChem nicht gefunden."
            case .network(let m): "PubChem nicht erreichbar: \(m)"
            }
        }
    }

    private var cache: [String: Result] = [:]
    private var running: [String: Task<Result, Error>] = [:]
    private let base = "https://pubchem.ncbi.nlm.nih.gov/rest"
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func lookup(_ rawCAS: String) async throws -> Result {
        guard let cas = CASNumber.normalized(rawCAS) else { throw LookupError.invalidCAS }
        if let hit = cache[cas] { return hit }
        // Gleiche CAS in mehreren Zeilen gleichzeitig: nur eine Anfrage
        if let task = running[cas] { return try await task.value }
        let task = Task { try await self.fetch(cas) }
        running[cas] = task
        defer { running[cas] = nil }
        let result = try await task.value
        cache[cas] = result
        return result
    }

    private func fetch(_ cas: String) async throws -> Result {
        let cidJSON = try await get("\(base)/pug/compound/name/\(cas)/cids/JSON", allowNotFound: true)
        guard let cidJSON, let cid = PubChemJSON.firstCID(cidJSON) else { throw LookupError.notFound }

        let propJSON = try await get("\(base)/pug/compound/cid/\(cid)/property/MolecularWeight,Title/JSON", allowNotFound: false)
        guard let propJSON, let props = PubChemJSON.properties(propJSON) else { throw LookupError.notFound }

        // Dichte fehlt bei vielen Feststoffen – dann 404, kein Fehler
        let densityJSON = try await get("\(base)/pug_view/data/compound/\(cid)/JSON?heading=Density", allowNotFound: true)
        let density = densityJSON.flatMap { PubChemDensity.parse(PubChemJSON.strings($0)) }
        return Result(title: props.title, molarMass: props.molarMass, density: density)
    }

    private func get(_ url: String, allowNotFound: Bool) async throws -> Data? {
        guard let u = URL(string: url) else { throw LookupError.notFound }
        do {
            let (data, response) = try await session.data(from: u)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 && allowNotFound { return nil }
            guard (200..<300).contains(status) else { throw LookupError.network("HTTP \(status)") }
            return data
        } catch let error as LookupError {
            throw error
        } catch {
            throw LookupError.network(error.localizedDescription)
        }
    }
}

// MARK: - CAS-Nummer

nonisolated enum CASNumber {
    /// Bringt die Eingabe in die Form "109-99-9" und prüft die Prüfziffer. `nil`, wenn ungültig.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{2013}", with: "-").replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2010}", with: "-").replacingOccurrences(of: "\u{2212}", with: "-")
        guard trimmed.range(of: #"^\d{2,7}-\d{2}-\d$"#, options: .regularExpression) != nil else { return nil }
        let digits = trimmed.filter(\.isNumber).compactMap(\.wholeNumberValue)
        let check = digits.last!
        let body = digits.dropLast().reversed()
        let sum = body.enumerated().reduce(0) { $0 + ($1.offset + 1) * $1.element }
        return sum % 10 == check ? trimmed : nil
    }

    static func isValid(_ raw: String) -> Bool { normalized(raw) != nil }
}

// MARK: - PubChem-Antworten

nonisolated enum PubChemJSON {
    static func firstCID(_ data: Data) -> Int? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["IdentifierList"] as? [String: Any],
              let cids = list["CID"] as? [Int] else { return nil }
        return cids.first
    }

    static func properties(_ data: Data) -> (title: String, molarMass: Double)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let table = obj["PropertyTable"] as? [String: Any],
              let first = (table["Properties"] as? [[String: Any]])?.first else { return nil }
        // MolecularWeight kommt als String ("72.11"), ältere Antworten als Zahl
        let mw = (first["MolecularWeight"] as? String).flatMap(Double.init) ?? (first["MolecularWeight"] as? Double)
        guard let mw, mw > 0 else { return nil }
        let title = (first["Title"] as? String) ?? ""
        return (title, mw)
    }

    /// Alle "String"-Werte aus einer pug_view-Antwort (die Dichteangaben stehen darin als Freitext).
    static func strings(_ data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [String] = []
        func walk(_ o: Any) {
            if let d = o as? [String: Any] {
                if let s = d["String"] as? String { out.append(s) }
                d.values.forEach(walk)
            } else if let a = o as? [Any] {
                a.forEach(walk)
            }
        }
        walk(obj)
        return out
    }
}

// MARK: - Dichte aus Freitext

/// Wählt aus PubChems Freitext-Angaben eine Dichte in g/cm³.
///
/// Beispiele aus PubChem: "0.8833 g/cu cm at 25 °C", "0.717 at 68 °F (USCG, 1999)", "0.7169 @ 20 °C/4 °C",
/// "Relative density (water = 1): 0.89", "2.29 g/cm³", "1.040-1.047", "Saturated liquid density: 55.230 lb/cu ft".
///
/// Bevorzugt werden ausdrückliche g/cm³-Angaben nahe Raumtemperatur (15–30 °C), dann relative Dichten nahe
/// Raumtemperatur, dann der Rest. Dampf-, Schütt- und lb-Angaben werden verworfen.
nonisolated enum PubChemDensity {
    static func parse(_ entries: [String]) -> Double? {
        var best: (score: Int, decimals: Int, value: Double)?
        for entry in entries {
            let lower = entry.lowercased()
            if ["vapor", "vapour", "bulk", "lb/", "lb ", "saturated", "gas density", "crystal"].contains(where: lower.contains) { continue }
            guard let (value, decimals, explicitUnit, factor) = firstValue(in: entry) else { continue }
            let density = value * factor
            guard density > 0.1, density < 25 else { continue }
            var score = explicitUnit ? 20 : 10
            if let t = temperatureCelsius(in: entry) {
                if (18...27).contains(t) { score += 5 } else if (15...30).contains(t) { score += 3 } else { score -= 5 }
            }
            // Bei gleicher Güte gewinnt die genauere Angabe ("1.3255" statt "1.3")
            if best == nil || score > best!.score || (score == best!.score && decimals > best!.decimals) {
                best = (score, decimals, density)
            }
        }
        return best.map { round($0.value * 10_000) / 10_000 }
    }

    /// Erste Zahl mit Einheit. Rückgabe: (Wert, Nachkommastellen, Einheit ausdrücklich angegeben, Faktor nach g/cm³).
    private static func firstValue(in s: String) -> (Double, Int, Bool, Double)? {
        guard let (v, explicit, factor) = firstValueRaw(in: s) else { return nil }
        return (v.value, v.decimals, explicit, factor)
    }

    private static func firstValueRaw(in s: String) -> ((value: Double, decimals: Int), Bool, Double)? {
        let number = #"(\d+(?:[.,]\d+)?)"#
        let units: [(String, Double)] = [
            (#"\s*(?:g/cu\.? ?cm|g/cm3|g/cm³|g\s*cm-3|g\s*cm⁻³|g/ml|g/mL)"#, 1),
            (#"\s*(?:kg/m3|kg/m³|kg\s*m-3)"#, 0.001),
            (#"\s*(?:kg/l|kg/L|kg/dm3|kg/dm³)"#, 1),
        ]
        for (unit, factor) in units {
            if let r = s.range(of: number + unit, options: [.regularExpression, .caseInsensitive]),
               let v = leadingNumber(String(s[r])) { return (v, true, factor) }
        }
        // Relative Dichte / Zahl am Anfang ("0.717 at 68 °F", "Relative density (water = 1): 0.89", "5.67")
        if let r = s.range(of: #"(?:water\s*=\s*1\)?:?\s*)"# + number, options: [.regularExpression, .caseInsensitive]) {
            let tail = String(s[r]).components(separatedBy: CharacterSet(charactersIn: ":)")).last ?? ""
            if let v = leadingNumber(tail.trimmingCharacters(in: .whitespaces)) { return (v, false, 1) }
        }
        if s.range(of: #"^\s*"# + number + #"(?:\s*$|\s+(?:at|@)\b|\s*@|\s+-?\d+(?:\.\d+)?\s*°)"#, options: .regularExpression) != nil,
           let v = leadingNumber(s.trimmingCharacters(in: .whitespaces)) {
            return (v, false, 1)
        }
        return nil
    }

    private static func leadingNumber(_ s: String) -> (value: Double, decimals: Int)? {
        guard let r = s.range(of: #"\d+(?:[.,]\d+)?"#, options: .regularExpression),
              let v = Double(s[r].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let text = String(s[r]).replacingOccurrences(of: ",", with: ".")
        return (v, text.split(separator: ".").dropFirst().first?.count ?? 0)
    }

    /// Temperatur aus "at 25 °C", "@ 20 °C/4 °C", "at 68 °F" in °C.
    private static func temperatureCelsius(in s: String) -> Double? {
        guard let r = s.range(of: #"(-?\d+(?:\.\d+)?)\s*°\s*([CF])"#, options: .regularExpression) else { return nil }
        let part = String(s[r])
        guard let v = leadingNumber(part)?.value else { return nil }
        let signed = part.hasPrefix("-") ? -v : v
        return part.hasSuffix("F") ? (signed - 32) * 5 / 9 : signed
    }
}
