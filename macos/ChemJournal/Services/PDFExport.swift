import AppKit
import Foundation
import PDFKit
import WebKit

// MARK: - PDF-Erzeugung

/// Druckt HTML (inkl. MathJax aus der App, offline) aus einem unsichtbaren WKWebView auf A4-Seiten.
///
/// - Echter Druck statt Bildschirmfoto: Inhalt, der nicht mehr auf die Seite passt, kommt automatisch auf die nächste;
///   Tabellenzeilen werden nicht zerschnitten, Tabellenköpfe wiederholen sich auf Folgeseiten.
/// - Danach Fußzeile mit Seitenzahl („Seite 2 von 5“).
/// - Aufträge laufen nacheinander (vorher hat ein zweiter Export den ersten abgebrochen).
final class PDFManager: NSObject, WKNavigationDelegate {
    static let shared = PDFManager()

    /// A4 in Punkt und Seitenränder (unten mehr Platz für die Fußzeile).
    static let pageSize = NSSize(width: 595.28, height: 841.89)
    static let margins = NSEdgeInsets(top: 42, left: 48, bottom: 54, right: 48)

    private struct Job { let html: String; let footer: String; let completion: (Data?) -> Void }
    private var queue: [Job] = []
    private var current: Job?
    private var webView: WKWebView?
    /// Unsichtbares Fenster: WebKit druckt nur Ansichten, die in einem Fenster liegen.
    private var window: NSWindow?
    private var outputURL: URL?

    /// - Parameter footer: links in der Fußzeile, z. B. Projekt- oder Ansatzname.
    func generatePDF(from html: String, footer: String = "", completion: @escaping (Data?) -> Void) {
        queue.append(Job(html: html, footer: footer, completion: completion))
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard current == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        current = job
        let config = WKWebViewConfiguration()
        config.preferences.shouldPrintBackgrounds = true
        // MathJax aus der App; meldet über `window.mathJaxDone`, wann alle Formeln gesetzt sind
        MathJaxResource.install(in: config, startup: "pageReady: () => MathJax.startup.defaultPageReady().then(() => { window.mathJaxDone = true; }, () => { window.mathJaxDone = true; })")
        let width = Self.pageSize.width - Self.margins.left - Self.margins.right
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: Self.pageSize.height), configuration: config)
        wv.navigationDelegate = self
        let win = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: Self.pageSize.height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = wv
        window = win
        webView = wv
        wv.loadHTMLString(job.html, baseURL: nil)
    }

    private func finish(_ data: Data?) {
        let job = current
        current = nil
        webView = nil
        window?.close()
        window = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        job?.completion(data)
        startNextIfIdle()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitForMathJax(webView, deadline: Date().addingTimeInterval(8))
    }

    /// Wartet, bis MathJax alle Formeln gesetzt hat (höchstens bis `deadline`), dann drucken.
    private func waitForMathJax(_ webView: WKWebView, deadline: Date) {
        webView.evaluateJavaScript("window.mathJaxDone === true") { [weak self] result, _ in
            guard let self, self.webView === webView else { return }
            if (result as? Bool) == true || Date() > deadline {
                self.print(webView)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitForMathJax(webView, deadline: deadline) }
            }
        }
    }

    private func print(_ wv: WKWebView) {
        guard let window else { finish(nil); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ChemJournal-\(UUID().uuidString).pdf")
        outputURL = url
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = Self.pageSize
        info.topMargin = Self.margins.top
        info.bottomMargin = Self.margins.bottom
        info.leftMargin = Self.margins.left
        info.rightMargin = Self.margins.right
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let op = wv.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = wv.bounds   // ohne das bleiben die Seiten leer
        op.runModal(for: window, delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    /// Kommt auf einem Hintergrund-Thread an → auf den Haupt-Thread wechseln.
    @objc nonisolated private func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { self.printFinished(success: success) }
    }

    private func printFinished(success: Bool) {
        guard success, let url = outputURL, let document = PDFDocument(url: url) else {
            Swift.print("PDF-Druck fehlgeschlagen")
            finish(nil)
            return
        }
        finish(Self.addingFooter(to: document, text: current?.footer ?? ""))
    }

    /// Zeichnet „Text · Seite x von y“ unten auf jede Seite.
    static func addingFooter(to document: PDFDocument, text: String) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        let count = document.pageCount
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.5),
            .foregroundColor: NSColor(white: 0.45, alpha: 1),
        ]
        for i in 0..<count {
            guard let page = document.page(at: i) else { continue }
            var box = page.bounds(for: .mediaBox)
            ctx.beginPage(mediaBox: &box)
            page.draw(with: .mediaBox, to: ctx)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let y = margins.bottom / 2 - 4
            let left = NSAttributedString(string: text, attributes: attrs)
            left.draw(at: NSPoint(x: margins.left, y: y))
            let right = NSAttributedString(string: String(localized: "Seite \(i + 1) von \(count)"), attributes: attrs)
            right.draw(at: NSPoint(x: box.width - margins.right - right.size().width, y: y))
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPage()
        }
        ctx.closePDF()
        return data as Data
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Swift.print("WKWebView fehlgeschlagen: \(error)")
        finish(nil)
    }

    // Fehlte vorher: ohne diesen Fall blieb der Export bei Ladefehlern hängen
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Swift.print("WKWebView konnte nicht laden: \(error)")
        finish(nil)
    }
}

// MARK: - HTML

struct HTMLGenerator {
    static func generate(for experiments: [Experiment], projectName: String = "") -> String {
        let dateFmt = DateFormatter(); dateFmt.dateStyle = .long; dateFmt.timeStyle = .none; dateFmt.locale = AppLanguage.current.locale
        let e = htmlEscaped
        var body = ""
        for (index, exp) in experiments.enumerated() {
            body += "<article class='experiment\(index > 0 ? " new-page" : "")'>"
            var meta = [dateFmt.string(from: exp.createdAt)]
            if !projectName.isEmpty { meta.insert(e(projectName), at: 0) }
            meta.append(exp.stages.count == 1 ? String(localized: "1 Stufe") : String(localized: "\(exp.stages.count) Stufen"))
            body += """
            <header class="doc-header">
              <div class="eyebrow">ChemJournal</div>
              <h1>\(rich(exp.title.isEmpty ? String(localized: "Ohne Titel") : exp.title))</h1>
              <div class="meta">\(meta.joined(separator: "<span class='dot'>·</span>"))</div>
              \(exp.summary.isEmpty ? "" : "<p class='lead'>\(rich(exp.summary))</p>")
            </header>
            """
            for stage in exp.stages { body += stageHTML(stage) }
            body += "</article>"
        }
        return """
        <!DOCTYPE html><html lang="\(AppLanguage.current.rawValue)"><head><meta charset="utf-8">
        <style>\(css)</style></head><body>\(body)</body></html>
        """
    }

    private static func stageHTML(_ stage: Stage) -> String {
        let e = htmlEscaped
        var h = "<section class='stage'>"
        h += "<h2>\(rich(stage.title))</h2>"
        if !stage.sourceURL.isEmpty {
            h += "<div class='source'><span class='label-inline'>\(String(localized: "Literatur"))</span> \(e(stage.sourceURL))</div>"
        }
        if !stage.summary.isEmpty { h += block(String(localized: "Zusammenfassung"), rich(stage.summary)) }
        if let data = stage.reactionImageData {
            h += "<figure class='scheme'><img src='data:image/png;base64,\(data.base64EncodedString())'></figure>"
        }
        if !stage.chemicals.isEmpty {
            h += "<div class='block\(stage.chemicals.count <= keepTogetherRows ? " keep" : "")'><div class='label'>\(String(localized: "Reagenzien"))</div><table class='chem'>"
            h += "<colgroup><col style='width:27%'><col style='width:13%'><col style='width:7%'><col style='width:10%'><col style='width:9%'><col style='width:11%'><col style='width:11%'><col style='width:12%'></colgroup>"
            h += "<thead><tr>\(th(String(localized: "Verbindung"), left: true))\(th("CAS", left: true))\(th("eq"))\(th("M", "g/mol"))\(th("d", "g/cm³"))\(th("n", "mol"))\(th("V", "mL"))\(th("m", "g"))</tr></thead><tbody>"
            for c in stage.chemicals {
                h += "<tr><td class='name'>\(nameHTML(c.name))</td><td class='cas'>\(e(c.cas))</td>\(num(c.equivalents))\(num(c.molarMass))\(num(c.density))\(num(c.amount))\(num(c.volume))\(num(c.mass))</tr>"
            }
            h += "</tbody></table></div>"
        }
        if !stage.procedure.isEmpty { h += block(String(localized: "Durchführung"), rich(stage.procedure)) }
        if !stage.observation.isEmpty { h += block(String(localized: "Beobachtung"), rich(stage.observation)) }
        if !stage.yieldProducts.isEmpty {
            h += "<div class='block\(stage.yieldProducts.count <= keepTogetherRows ? " keep" : "")'><div class='label'>\(String(localized: "Ausbeute"))</div><table class='yield'>"
            h += "<colgroup><col style='width:30%'><col style='width:14%'><col style='width:12%'><col style='width:12%'><col style='width:14%'><col style='width:18%'></colgroup>"
            h += "<thead><tr>\(th(String(localized: "Produkt"), left: true))\(th("CAS", left: true))\(th("M", "g/mol"))\(th("m", "g"))\(th(String(localized: "m theor."), "g"))\(th(String(localized: "Ausbeute")))</tr></thead><tbody>"
            for y in stage.yieldProducts {
                let ref = y.referenceChemicalID.flatMap { id in stage.chemicals.first { $0.id == id } }
                let refN = ref.flatMap { parseDecimal($0.amount) }
                var mTheor = ""
                if let refN, let M = parseDecimal(y.molarMass) { mTheor = format3(refN * M) }
                var yPct = ""
                if let refN, refN > 0, let myN = parseDecimal(y.amount), myN > 0 { yPct = String(format: "%.1f %%", (myN / refN) * 100) }
                h += "<tr><td class='name'>\(nameHTML(y.name))</td><td class='cas'>\(e(y.cas))</td>\(num(y.molarMass))\(num(y.mass))\(num(mTheor))<td class='num strong'>\(e(yPct))</td></tr>"
            }
            h += "</tbody></table></div>"
        }
        return h + "</section>"
    }

    /// Tabellen bis zu dieser Länge werden nie über zwei Seiten verteilt (samt Überschrift auf die nächste Seite).
    static let keepTogetherRows = 18

    private static func block(_ label: String, _ content: String) -> String {
        "<div class='block'><div class='label'>\(label)</div><div class='text'>\(content)</div></div>"
    }

    private static func th(_ title: String, _ unit: String? = nil, left: Bool = false) -> String {
        "<th\(left ? " class='left'" : "")>\(title)\(unit.map { "<span class='unit'>\($0)</span>" } ?? "")</th>"
    }

    private static func num(_ s: String) -> String { "<td class='num'>\(htmlEscaped(s))</td>" }

    /// Freitext: HTML maskiert, Zeilenumbrüche, Formeln in `$…$` und `\ce{…}` über MathJax (wie in der Vorschau).
    static func rich(_ text: String) -> String { LaTeXEditorView.previewHTML(text) }

    /// Name in einer Tabellenzeile.
    /// - Steht `$…$` oder `\ce{…}` darin, setzt MathJax genau das.
    /// - Sonst normaler Text in der Schrift des Dokuments; nur Wörter, die wie eine Summenformel aussehen
    ///   (CH2Cl2, NEt3, Pd(PPh3)4, CuSO4·5H2O), bekommen tiefgestellte Ziffern. „Propionsäure 1“ bleibt Text.
    static func nameHTML(_ name: String) -> String {
        if name.contains("$") || name.contains("\\ce{") { return rich(name) }
        return name.split(separator: " ", omittingEmptySubsequences: false).map { word in
            let w = String(word)
            return looksLikeFormula(w) ? subscriptDigits(w) : htmlEscaped(w)
        }.joined(separator: " ")
    }

    static func looksLikeFormula(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase || first == "(" || first == "[" else { return false }
        guard word.range(of: #"^(?:[A-Z][a-z]?|[0-9]+|[()\[\]·•])+$"#, options: .regularExpression) != nil else { return false }
        return word.range(of: #"[A-Za-z\)\]][0-9]"#, options: .regularExpression) != nil
    }

    /// Ziffern nach einem Buchstaben oder einer Klammer tiefstellen; Faktoren nach „·“ (5H2O) bleiben normal.
    static func subscriptDigits(_ word: String) -> String {
        var out = ""
        var previous: Character?
        var inSub = false
        for c in word {
            let sub = c.isNumber && (inSub || previous.map { $0.isLetter || $0 == ")" || $0 == "]" } ?? false)
            if sub && !inSub { out += "<sub>" }
            if !sub && inSub { out += "</sub>" }
            inSub = sub
            out += htmlEscaped(String(c))
            previous = c
        }
        if inSub { out += "</sub>" }
        return out
    }

    private static let css = """
    @page { size: A4; }
    * { box-sizing: border-box; }
    html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    body { margin: 0; font-family: -apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 9.5pt;
           line-height: 1.45; color: #1d1d1f; hyphens: auto; -webkit-hyphens: auto; }
    .new-page { break-before: page; }
    .doc-header { border-bottom: 1.5pt solid #1d1d1f; padding-bottom: 8pt; margin-bottom: 14pt; }
    .eyebrow { font-size: 8.5pt; letter-spacing: .02em; color: #6e6e73; font-weight: 600; text-align: right; }
    h1 { font-size: 18pt; line-height: 1.2; margin: 2pt 0 4pt; font-weight: 700; }
    .meta { font-size: 8.5pt; color: #6e6e73; }
    .dot { margin: 0 5pt; }
    .lead { margin: 8pt 0 0; font-size: 10pt; color: #3a3a3c; }
    .stage { margin-top: 16pt; }
    .stage + .stage { border-top: .5pt solid #d2d2d7; padding-top: 12pt; }
    h2 { font-size: 12.5pt; margin: 0 0 6pt; font-weight: 650; break-after: avoid; }
    .source { font-size: 8.5pt; color: #3a3a3c; margin-bottom: 6pt; overflow-wrap: anywhere; }
    .label-inline { font-weight: 600; color: #6e6e73; margin-right: 4pt; }
    .block { margin-top: 10pt; }
    .label { font-size: 7.5pt; letter-spacing: .1em; text-transform: uppercase; color: #6e6e73; font-weight: 600;
             margin-bottom: 3pt; break-after: avoid; }
    .text { overflow-wrap: anywhere; }
    figure.scheme { margin: 10pt 0; text-align: center; break-inside: avoid; }
    figure.scheme img { max-width: 100%; max-height: 210pt; object-fit: contain; }
    table { width: 100%; border-collapse: collapse; table-layout: fixed; font-size: 8.5pt; }
    .keep, figure.scheme { break-inside: avoid; page-break-inside: avoid; }
    thead { display: table-header-group; break-inside: avoid; }
    tr, th { break-inside: avoid; page-break-inside: avoid; }
    th { font-weight: 600; font-size: 7.5pt; color: #3a3a3c; text-align: right; vertical-align: bottom;
         padding: 4pt 5pt; border-bottom: 1pt solid #1d1d1f; background: #f5f5f7; }
    th.left { text-align: left; }
    th .unit { display: block; font-weight: 400; color: #86868b; }
    td { padding: 4pt 5pt; border-bottom: .5pt solid #d2d2d7; vertical-align: top; overflow-wrap: anywhere; }
    tbody tr:nth-child(even) td { background: #fafafa; }
    td.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    td.strong { font-weight: 600; }
    td.cas { font-variant-numeric: tabular-nums; color: #3a3a3c; white-space: nowrap; font-size: 8pt; }
    td.name { font-weight: 500; }
    sub { font-size: 70%; line-height: 0; vertical-align: -0.3em; }
    mjx-container { max-width: 100%; }
    mjx-container svg { max-width: 100%; height: auto; }
    """
}
