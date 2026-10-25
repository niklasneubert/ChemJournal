// pdf_text.swift – gibt den Text eines PDFs so aus, wie PDFKit ihn beim Kopieren liefert
// (inklusive der typischen Artefakte). Hilfreich, um neue Fälle fürs Korpus zu sammeln.
//
//   swift Tools/SmartExtractEval/pdf_text.swift "Pfad/zur/SI.pdf" > si.txt

import Foundation
import PDFKit

guard CommandLine.arguments.count > 1, let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    FileHandle.standardError.write(Data("Aufruf: swift pdf_text.swift Datei.pdf\n".utf8))
    exit(1)
}
for i in 0..<doc.pageCount {
    print("<<<Seite \(i + 1)>>>")
    print(doc.page(at: i)?.string ?? "")
}
