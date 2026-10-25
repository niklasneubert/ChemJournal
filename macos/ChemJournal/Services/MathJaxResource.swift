import Foundation
import WebKit

/// MathJax 3.2.2 (SVG-Ausgabe, alle TeX-Erweiterungen inkl. mhchem) liegt in der App – Formeln werden
/// ohne Internet gesetzt. Quelle: npm-Paket `mathjax@3.2.2`, Datei `es5/tex-svg-full.js` (Apache-2.0,
/// Lizenz in `Resources/MathJax/MathJax-LICENSE.txt`).
enum MathJaxResource {
    /// Einmal gelesen und von allen Vorschau-Feldern und dem PDF-Export geteilt.
    static let script: String? = Bundle.main.url(forResource: "mathjax-tex-svg-full", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// TeX-Einstellungen wie bisher: `$…$` inline, `$$…$$` abgesetzt, `\ce{…}` über mhchem.
    static let texConfig = "tex: { inlineMath: [['$','$']], displayMath: [['$$','$$']], packages: {'[+]': ['mhchem']} }"

    /// Lädt MathJax in jede Seite dieses WebViews, sobald das Dokument aufgebaut ist.
    /// (Bei `.atDocumentStart` startet MathJax nie: Es wartet auf ein Seitenereignis, das dort nicht mehr kommt.)
    /// - Parameter startup: zusätzlicher Inhalt für `MathJax.startup` (z. B. `typeset: false`).
    static func install(in configuration: WKWebViewConfiguration, startup: String) {
        let controller = configuration.userContentController
        let config = "window.MathJax = { \(texConfig), svg: { fontCache: 'global' }, startup: { \(startup) } };"
        controller.addUserScript(WKUserScript(source: config, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        if let script {
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        } else {
            print("ChemJournal: MathJax fehlt im App-Bundle – Formeln werden nicht gesetzt.")
        }
    }
}
