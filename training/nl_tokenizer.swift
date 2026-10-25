// nl_tokenizer.swift – Tokenisiert Texte exakt so, wie ChemJournal es zur Laufzeit tut.
//
// Wird von dataset_builder.py automatisch gebaut und aufgerufen:
//   swiftc -O nl_tokenizer.swift ChemJournal/Services/SmartExtract/SynthesisTextNormalizer.swift \
//          ChemJournal/Services/SmartExtract/SynthesisLexicon.swift -o <cache>/nl_tokenizer
//
// Eingabe (stdin):  eine JSON-Zeile pro Text: {"id": "...", "text": "..."}
// Ausgabe (stdout): eine JSON-Zeile pro Text: {"id": "...", "normalized": "...", "tokens": [[start, end], ...]}
//
// Offsets zählen Unicode-Codepoints (wie Python-Strings). Die Tokens sind die, die NLTagger mit
// `.omitWhitespace` liefert – also inklusive Satzzeichen. Genau diese Folge sieht das Create-ML-Modell
// in der App (siehe SmartExtractor.tokenize).

import Foundation
import NaturalLanguage

struct Input: Decodable { let id: String; let text: String }
struct Output: Encodable { let id: String; let normalized: String; let tokens: [[Int]] }

@main
struct NLTokenizerTool {
    static func main() throws {
        let language = NLLanguage(CommandLine.arguments.dropFirst().first ?? "en")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        while let line = readLine(strippingNewline: true) {
            try process(line, language: language, encoder: encoder, decoder: decoder)
        }
    }
}

func process(_ line: String, language: NLLanguage, encoder: JSONEncoder, decoder: JSONDecoder) throws {
    guard !line.isEmpty, let input = try? decoder.decode(Input.self, from: Data(line.utf8)) else { return }
    let text = normalizeSynthesisText(input.text)
    let tagger = NLTagger(tagSchemes: [.tokenType])
    tagger.string = text
    let whole = text.startIndex..<text.endIndex
    tagger.setLanguage(language, range: whole)

    // Codepoint-Offsets für alle Indizes einmal vorberechnen
    var offsets: [String.Index: Int] = [:]
    var i = 0
    for idx in text.unicodeScalars.indices { offsets[idx] = i; i += 1 }
    offsets[text.endIndex] = i

    var tokens: [[Int]] = []
    tagger.enumerateTags(in: whole, unit: .word, scheme: .tokenType, options: [.omitWhitespace]) { _, range in
        let s = offsets[range.lowerBound] ?? text.unicodeScalars.distance(from: text.startIndex, to: range.lowerBound)
        let e = offsets[range.upperBound] ?? text.unicodeScalars.distance(from: text.startIndex, to: range.upperBound)
        tokens.append([s, e])
        return true
    }
    let data = try encoder.encode(Output(id: input.id, normalized: text, tokens: tokens))
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
