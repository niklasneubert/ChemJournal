import SwiftUI
import WebKit

/// Textfeld mit automatischer Formel-Vorschau.
///
/// - Im Feld: LaTeX-Quelltext bearbeiten (`$…$`, `\ce{…}`).
/// - Feld verlassen: Formeln werden im Hintergrund gesetzt; ist das fertig, blendet die Vorschau weich ein
///   (kein Aufblitzen des Quelltexts).
/// - Klick auf die Vorschau: zurück in den Quelltext, Cursor sofort im Feld.
/// - Text ohne Formeln bleibt einfach als Text stehen.
struct LaTeXEditorView: View {
    var title: String
    @Binding var text: String

    @FocusState private var isFocused: Bool
    /// Text, den die Vorschau gerade fertig gesetzt anzeigt.
    @State private var renderedText: String?
    @State private var previewHeight: CGFloat = 0

    private var hasFormulas: Bool { Self.containsFormulas(text) }
    private var showPreview: Bool { !isFocused && hasFormulas && renderedText == text }

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .scrollDisabled(true)
                    .font(.body)
                    .focused($isFocused)
                    .frame(minHeight: 80)
                    .frame(height: showPreview ? max(previewHeight, 80) : nil)
                    .padding(8)
                    .opacity(showPreview ? 0 : 1)

                if hasFormulas {
                    MathJaxView(text: text, shouldRender: !isFocused) { rendered, height in
                        previewHeight = height
                        withAnimation(.easeOut(duration: 0.15)) { renderedText = rendered }
                    }
                    // Versteckt: 1 pt hoch, damit sie das Feld beim Tippen nicht vergrößert, aber weiter setzt
                    .frame(height: showPreview ? max(previewHeight, 80) + 16 : 1)
                    .opacity(showPreview ? 1 : 0)
                    .overlay {
                        // Klick auf die Vorschau → Quelltext bearbeiten
                        if showPreview {
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture { isFocused = true }
                                .pointerStyle(.horizontalText)
                        }
                    }
                    .accessibilityHidden(!showPreview)
                }
            }
            .clipped()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1))
            .animation(.easeOut(duration: 0.15), value: showPreview)
        }
    }

    /// Nur Text mit `$…$` oder `\ce{…}` braucht MathJax.
    static func containsFormulas(_ text: String) -> Bool {
        text.contains("$") || text.contains("\\ce{")
    }

    /// Gleiche Umwandlung wie bisher: HTML maskieren, Zeilenumbrüche, nacktes `\ce{…}` in `$…$` setzen.
    static func previewHTML(_ text: String) -> String {
        var fmt = htmlEscaped(text).replacingOccurrences(of: "\n", with: "<br>")
        fmt = fmt.replacingOccurrences(of: #"(?<!\$)\\ce\{([^}]+)\}"#, with: #"$\\ce{$1}$"#, options: .regularExpression)
        return fmt
    }
}

/// MathJax-Vorschau. Die Seite wird nur einmal geladen; neue Inhalte werden per JavaScript abseits des
/// Sichtbereichs gesetzt und erst dann eingetauscht. Meldet danach die Höhe des Inhalts.
struct MathJaxView: NSViewRepresentable {
    var text: String
    /// Nur setzen, wenn das Feld nicht bearbeitet wird (spart Arbeit beim Tippen).
    var shouldRender: Bool
    var onRendered: (_ text: String, _ height: CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptHandler(context.coordinator), name: "rendered")
        MathJaxResource.install(in: config, startup: "typeset: false")
        let wv = PassthroughWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        wv.loadHTMLString(Self.page, baseURL: nil)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onRendered = onRendered
        guard shouldRender else { return }
        context.coordinator.request(text)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "rendered")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onRendered: ((String, CGFloat) -> Void)?
        private var isLoaded = false
        private var requested: String?
        private var inFlight: String?
        private var lastRendered: String?

        func request(_ text: String) {
            guard text != lastRendered || inFlight != nil else { return }
            requested = text
            sendIfPossible()
        }

        private func sendIfPossible() {
            guard isLoaded, inFlight == nil, let text = requested, let webView else { return }
            requested = nil
            if text == lastRendered { return }
            inFlight = text
            let html = LaTeXEditorView.previewHTML(text)
            guard let data = try? JSONEncoder().encode(html), let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("render(\(json))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            sendIfPossible()
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            // Nur die eigene Seite laden; Links aus dem Text nicht im Feld öffnen
            decisionHandler(action.navigationType == .other ? .allow : .cancel)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let height = (message.body as? NSNumber).map { CGFloat(truncating: $0) } ?? 0
            if let text = inFlight {
                lastRendered = text
                inFlight = nil
                onRendered?(text, height)
            } else if let text = lastRendered {
                onRendered?(text, height)   // Breite geändert → neue Höhe
            }
            sendIfPossible()
        }
    }

    /// Verhindert den Retain-Zyklus WKUserContentController → Handler.
    private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            target?.userContentController(c, didReceive: m)
        }
    }

    /// Nimmt keine Maus-/Scroll-Ereignisse an: Klicks gehen an das Feld, das Mausrad scrollt die Seite.
    private final class PassthroughWebView: WKWebView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    }

    /// Feste Seite mit `render(html)`. MathJax kommt aus der App (`MathJaxResource`) – funktioniert offline.
    static let page = """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <script>
    let busy = Promise.resolve();
    function report() {
      const h = document.getElementById('content').getBoundingClientRect().height;
      window.webkit.messageHandlers.rendered.postMessage(Math.ceil(h));
    }
    function ready() {
      return new Promise(resolve => {
        const t0 = Date.now();
        (function wait() {
          if (window.MathJax && MathJax.typesetPromise && MathJax.startup && MathJax.startup.promise) {
            MathJax.startup.promise.then(resolve);
          } else if (Date.now() - t0 > 4000) { resolve(); }   // MathJax fehlt: Text ungesetzt zeigen
          else { setTimeout(wait, 30); }
        })();
      });
    }
    function render(html) {
      busy = busy.then(async () => {
        const stage = document.getElementById('stage');
        stage.style.width = document.getElementById('content').clientWidth + 'px';
        stage.innerHTML = html;
        await ready();
        if (window.MathJax && MathJax.typesetPromise) {
          try { MathJax.typesetClear(); await MathJax.typesetPromise([stage]); } catch (e) {}
        }
        const content = document.getElementById('content');
        content.replaceChildren(...stage.childNodes);
        report();
      });
    }
    new ResizeObserver(() => report()).observe(document.documentElement);
    </script>
    <style>
      :root { color-scheme: light dark; }
      html, body { margin: 0; padding: 0; overflow: hidden; background: transparent; }
      body { font: 13px -apple-system, BlinkMacSystemFont, sans-serif; line-height: 1.35; }
      #content { padding: 8px 13px; overflow-wrap: anywhere; }
      #stage { position: absolute; left: -10000px; top: 0; visibility: hidden; padding: 8px 13px; box-sizing: border-box; }
    </style></head>
    <body><div id="content"></div><div id="stage"></div></body></html>
    """
}
