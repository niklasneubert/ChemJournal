import Foundation
import Testing
import WebKit
@testable import ChemJournal

/// Formeln müssen ohne Internet gesetzt werden: Jeder http(s)-Zugriff wird in diesen Tests blockiert.
@Suite("Formeln offline (MathJax in der App)")
@MainActor
struct OfflineMathJaxTests {

    private final class Collector: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var heights: [CGFloat] = []
        var loaded = false
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            heights.append((m.body as? NSNumber).map { CGFloat(truncating: $0) } ?? -1)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    }

    private func blockNetwork(_ config: WKWebViewConfiguration) async throws {
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "ChemJournalTestsOffline", encodedContentRuleList: rules)
        config.userContentController.add(try #require(list))
    }

    private func wait(timeout: TimeInterval = 10, until condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test("MathJax liegt im App-Bundle")
    func bundled() throws {
        let script = try #require(MathJaxResource.script)
        #expect(script.count > 2_000_000)
        #expect(script.contains("mhchem"))
    }

    @Test("Seiten verweisen auf kein Netz mehr")
    func noCDN() {
        #expect(!MathJaxView.page.contains("http"))
        #expect(!HTMLGenerator.generate(for: [Experiment(title: "A", summary: "")]).contains("<script"))
    }

    @Test("Vorschau setzt \\ce{} und $…$ ohne Internet")
    func previewOffline() async throws {
        let config = WKWebViewConfiguration()
        try await blockNetwork(config)
        let collector = Collector()
        config.userContentController.add(collector, name: "rendered")
        MathJaxResource.install(in: config, startup: "typeset: false")
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 200), configuration: config)
        wv.navigationDelegate = collector
        wv.loadHTMLString(MathJaxView.page, baseURL: nil)
        #expect(await wait { collector.loaded })

        let html = LaTeXEditorView.previewHTML("Ausbeute von \\ce{H2SO4} bei $T = 25^\\circ$")
        let json = String(data: try JSONEncoder().encode(html), encoding: .utf8)!
        _ = try? await wv.evaluateJavaScript("render(\(json)); 0")
        #expect(await wait { !collector.heights.isEmpty })

        let svgCount = try await wv.evaluateJavaScript("document.querySelectorAll('#content mjx-container svg').length") as? Int
        #expect(svgCount == 2)
        let raw = try await wv.evaluateJavaScript("document.getElementById('content').textContent") as? String
        #expect(raw?.contains("\\ce") == false)        // Quelltext ist ersetzt
        #expect((collector.heights.last ?? 0) > 0)
    }

    @Test("PDF-Export setzt Formeln ohne Internet")
    func pdfOffline() async throws {
        var stage = Stage(title: "Stufe 1")
        stage.chemicals = [ChemicalData(name: "CuI")]
        stage.procedure = "Lösung von $\\ce{NaHCO3}$"
        let html = HTMLGenerator.generate(for: [Experiment(title: "A", summary: "", stages: [stage])])

        let config = WKWebViewConfiguration()
        try await blockNetwork(config)
        MathJaxResource.install(in: config, startup: "pageReady: () => MathJax.startup.defaultPageReady().then(() => { window.mathJaxDone = true; })")
        let collector = Collector()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842), configuration: config)
        wv.navigationDelegate = collector
        wv.loadHTMLString(html, baseURL: nil)
        #expect(await wait { collector.loaded })
        #expect(await wait { (try? await wv.evaluateJavaScript("window.mathJaxDone === true") as? Bool) == true })
        let svgCount = try await wv.evaluateJavaScript("document.querySelectorAll('mjx-container svg').length") as? Int
        #expect(svgCount == 1)   // NaHCO3 im Text; „CuI“ in der Tabelle ist normaler Text
    }
}
