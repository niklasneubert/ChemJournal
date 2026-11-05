import AppKit
import SwiftUI

// MARK: - Zustand

/// Gemeinsamer Zustand des Taschenrechners – Popover und abgelöstes Fenster zeigen dieselbe Rechnung.
@MainActor @Observable
final class CalculatorModel {
    static let shared = CalculatorModel()

    private(set) var engine = CalculatorEngine()
    /// Cursor bzw. Auswahl im Rechenfeld (Zeichen-Offsets) – bleibt bekannt, auch wenn das Feld gerade nicht aktiv ist.
    var selection = NSRange(location: 0, length: 0)
    /// Wird bei Änderungen über die Tasten erhöht: Das Feld übernimmt dann Text und Cursor.
    private(set) var revision = 0
    /// Wird erhöht, wenn das Rechenfeld den Tastaturfokus bekommen soll.
    private(set) var focusRequest = 0
    /// Escape im Rechenfeld (im Popover: schließen).
    @ObservationIgnored var onEscape: () -> Void = {}

    /// Taste an der Cursorposition; eine Auswahl wird ersetzt.
    func press(_ key: CalculatorEngine.Key) {
        let count = engine.expression.count
        var sel = selection
        sel.location = min(max(sel.location, 0), count)
        sel.length = min(max(sel.length, 0), count - sel.location)
        if sel.length > 0, key != .equals, key != .clear {
            var chars = Array(engine.expression)
            chars.removeSubrange(sel.location..<(sel.location + sel.length))
            engine.setExpression(String(chars))
            if key == .backspace { finish(at: sel.location); return }
        }
        finish(at: engine.press(key, at: sel.location))
    }

    /// Text von Hand im Feld geändert (Einfügen, Löschen, …).
    func userEdited(_ expression: String, selection: NSRange) {
        engine.setExpression(expression)
        self.selection = selection
    }

    func requestFocus() { focusRequest += 1 }

    private func finish(at cursor: Int) {
        selection = NSRange(location: cursor, length: 0)
        revision += 1
        focusRequest += 1
    }
}

// MARK: - Popover und schwebendes Fenster

/// Öffnet den Taschenrechner als Popover am Knopf. Zieht man das Popover am Rand weg, löst es sich als kleines,
/// frei schwebendes Fenster (mit Schließen-Knopf), das offen bleibt, bis man es schließt oder ChemJournal beendet.
@MainActor
final class CalculatorController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    static let shared = CalculatorController()

    private let model = CalculatorModel.shared
    private var popover: NSPopover?
    private var panel: NSPanel?

    override init() {
        super.init()
        // Schwebt nur über anderen Fenstern, solange ChemJournal vorne ist
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.level = .floating }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.level = .normal }
        }
        // Erscheinungsbild von ChemJournal (Darstellung › Erscheinungsbild) übernehmen – das abgelöste Fenster ist ein
        // eigenes Fenster und folgte sonst dem System statt der App-Einstellung
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            model.requestFocus()
            return
        }
        if let popover, popover.isShown { popover.performClose(nil); return }
        show()
    }

    private func show() {
        let event = NSApp.currentEvent
        guard let window = event?.window ?? NSApp.keyWindow ?? NSApp.mainWindow,
              let frameView = window.contentView?.superview ?? window.contentView else { return }
        // Am Knopf unter dem Mauszeiger andocken; sonst oben mittig im Fenster
        var anchor: NSView = frameView
        var rect: NSRect
        if let event, event.window === window {
            let point = event.locationInWindow
            if var hit = frameView.hitTest(point) {
                while hit.bounds.width < 22, let up = hit.superview { hit = up }
                if hit.bounds.width <= 80 { anchor = hit }
            }
            rect = anchor === frameView
                ? NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
                : anchor.bounds
        } else {
            rect = NSRect(x: frameView.bounds.midX - 1, y: frameView.bounds.maxY - 60, width: 2, height: 2)
        }

        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        p.contentViewController = makeContent()
        model.onEscape = { [weak p] in p?.performClose(nil) }
        p.show(relativeTo: rect, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
        popover = p
        applyAppearance()
        model.requestFocus()
    }

    private func makeContent() -> NSViewController {
        let vc = NSHostingController(rootView: CalculatorPanel(model: model))
        vc.sizingOptions = [.preferredContentSize]
        vc.title = String(localized: "Taschenrechner")
        return vc
    }

    // Ablösen

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    /// Hell/Dunkel wie in ChemJournal eingestellt („System“ = wie macOS).
    private func applyAppearance() {
        let appearance: NSAppearance? = switch UserDefaults.standard.string(forKey: "appTheme") {
        case AppTheme.dark.rawValue: NSAppearance(named: .darkAqua)
        case AppTheme.light.rawValue: NSAppearance(named: .aqua)
        default: nil
        }
        if panel?.appearance != appearance { panel?.appearance = appearance }
        if let popover, popover.appearance != appearance { popover.appearance = appearance }
    }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 276, height: 400),
                        styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true)
        p.title = String(localized: "Taschenrechner")
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.delegate = self
        let vc = makeContent()
        p.contentViewController = vc
        p.setContentSize(vc.view.fittingSize)
        panel = p
        applyAppearance()
        return p
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        model.onEscape = {}
    }

    func windowDidBecomeKey(_ notification: Notification) { model.requestFocus() }
}

/// Knopf in der Symbolleiste.
struct CalculatorToolbarButton: View {
    var body: some View {
        Button { CalculatorController.shared.toggle() } label: {
            Label { Text("Taschenrechner") } icon: { Image("action.calculator") }
        }
        .help("Taschenrechner – am Rand wegziehen, um ihn als eigenes Fenster frei schweben zu lassen")
    }
}

// MARK: - Inhalt

/// Rechenfeld (anklicken, mit ← → bewegen, ⌫ löscht) mit Ergebnis darunter und Tastenfeld.
/// Tastatur: Ziffern, . oder , , + − * / ^ ( ) %, Return oder = rechnet, C setzt zurück.
struct CalculatorPanel: View {
    let model: CalculatorModel
    @AppStorage(CalculatorSeparator.defaultsKey) private var separatorRaw = CalculatorSeparator.point.rawValue
    @State private var copied = false

    private var separator: CalculatorSeparator { CalculatorSeparator(rawValue: separatorRaw) ?? .point }
    private var engine: CalculatorEngine { model.engine }

    /// Großes Ergebnis: nach „=“ das Ergebnis, sonst das Zwischenergebnis der laufenden Eingabe.
    private var resultText: String {
        if engine.hasError { return String(localized: "Fehler") }
        if let v = shownValue { return CalculatorEngine.format(v, separator: separator) }
        return engine.expression.isEmpty ? "0" : " "
    }

    private var shownValue: Double? {
        if engine.hasError { return nil }
        return engine.showsResult ? engine.result : engine.currentValue
    }

    var body: some View {
        VStack(spacing: 10) {
            display
            keypad
        }
        .padding(12)
        .frame(width: 252)
    }

    private var display: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Button(action: copyResult) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(shownValue == nil)
                .help("Ergebnis kopieren")
                CalculatorExpressionField(model: model, text: engine.displayExpression(separator), separator: separator,
                                          revision: model.revision, focusRequest: model.focusRequest)
                    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
            }
            Text(resultText)
                .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(engine.hasError ? Color.red : (engine.showsResult ? Color.primary : Color.secondary))
                .lineLimit(1).minimumScaleFactor(0.4)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { model.requestFocus() }
    }

    private var keypad: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                key("√", .squareRoot, .function, help: "Wurzel")
                key("xʸ", .power, .function, help: "Potenz (^)")
                key("%", .percent, .function, help: "Prozent")
                key("⌫", .backspace, .function, help: "Letztes Zeichen löschen")
            }
            GridRow {
                key("C", .clear, .function, help: "Zurücksetzen (C)")
                key("(", .openParen, .function)
                key(")", .closeParen, .function)
                key("÷", .divide, .operator)
            }
            GridRow { digit(7); digit(8); digit(9); key("×", .multiply, .operator) }
            GridRow { digit(4); digit(5); digit(6); key("−", .subtract, .operator) }
            GridRow { digit(1); digit(2); digit(3); key("+", .add, .operator) }
            GridRow {
                key("±", .negate, .function, help: "Vorzeichen wechseln")
                digit(0)
                key(separator.rawValue, .decimal, .digit, help: "Dezimaltrennzeichen – in den Einstellungen wählbar")
                key("=", .equals, .equals)
            }
        }
    }

    private enum Style { case digit, function, `operator`, equals }

    private func digit(_ d: Int) -> some View { key("\(d)", .digit(d), .digit) }

    private func key(_ title: String, _ k: CalculatorEngine.Key, _ style: Style, help: LocalizedStringKey? = nil) -> some View {
        Button {
            model.press(k)
            copied = false
        } label: {
            Text(title)
                .font(.system(size: 17, weight: style == .digit ? .regular : .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(CalculatorKeyStyle(style: style))
        .focusable(false)
        .help(help.map { Text($0) } ?? Text(verbatim: ""))
    }

    private struct CalculatorKeyStyle: ButtonStyle {
        let style: Style
        func makeBody(configuration: Configuration) -> some View {
            let fill: Color = switch style {
            case .digit: Color.gray.opacity(0.16)
            case .function: Color.gray.opacity(0.30)
            case .operator: Color.accentColor.opacity(0.22)
            case .equals: Color.accentColor
            }
            return configuration.label
                .foregroundStyle(style == .equals ? Color.white : (style == .operator ? Color.accentColor : Color.primary))
                .background(fill.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func copyResult() {
        guard let v = shownValue else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CalculatorEngine.format(v, separator: separator), forType: .string)
        copied = true
    }
}

// MARK: - Rechenfeld

/// Einzeiliges Textfeld für die Rechnung. Getippte Zeichen laufen über den Rechenkern (z. B. „*“ → „×“, 2( → 2×( ),
/// Pfeiltasten, Mausklick und ⌫ funktionieren wie in jedem Textfeld.
struct CalculatorExpressionField: NSViewRepresentable {
    let model: CalculatorModel
    let text: String
    let separator: CalculatorSeparator
    let revision: Int
    let focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> CalculatorTextField {
        let f = CalculatorTextField()
        f.isBordered = false
        f.isBezeled = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.alignment = .right
        f.textColor = .labelColor
        let base = NSFont.systemFont(ofSize: 16)
        f.font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 16) } ?? base
        f.placeholderString = "0"
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        f.delegate = context.coordinator
        f.stringValue = text
        let c = context.coordinator
        c.field = f
        if let editor = f.calculatorEditor {
            editor.onKey = { [weak c] key, range in c?.typed(key, range) }
            editor.onSelectionChange = { [weak c] range in c?.selectionChanged(range) }
        }
        return f
    }

    func updateNSView(_ f: CalculatorTextField, context: Context) {
        let c = context.coordinator
        c.separator = separator
        if f.stringValue != text {
            c.quietly { f.stringValue = text }
            c.applySelection()
        }
        if c.appliedRevision != revision {
            c.appliedRevision = revision
            c.applySelection()
        }
        if c.appliedFocus != focusRequest {
            c.appliedFocus = focusRequest
            DispatchQueue.main.async { c.focus() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: CalculatorModel
        weak var field: CalculatorTextField?
        var separator = CalculatorSeparator.point
        var appliedRevision = -1
        var appliedFocus = 0
        private var muted = false

        init(model: CalculatorModel) { self.model = model }

        /// Änderungen, die nicht vom Nutzer kommen (Text setzen, Fokus), verändern die gemerkte Cursorposition nicht.
        func quietly(_ body: () -> Void) {
            let was = muted
            muted = true
            body()
            muted = was
        }

        func focus() {
            guard let f = field, let window = f.window else { return }
            if f.currentEditor() == nil { quietly { window.makeFirstResponder(f) } }
            applySelection()
        }

        func applySelection() {
            guard let editor = field?.currentEditor() else { return }
            let length = (editor.string as NSString).length
            var r = model.selection
            r.location = min(max(r.location, 0), length)
            r.length = min(max(r.length, 0), length - r.location)
            quietly { editor.selectedRange = r }
            editor.scrollRangeToVisible(r)
        }

        func selectionChanged(_ range: NSRange) {
            guard !muted, let f = field, let editor = f.currentEditor(), f.window?.firstResponder === editor else { return }
            model.selection = range
        }

        func typed(_ key: CalculatorEngine.Key, _ range: NSRange) {
            model.selection = range
            model.press(key)
            syncNow()
        }

        /// Feld sofort angleichen (nicht erst beim nächsten SwiftUI-Durchlauf) – sonst landet beim schnellen Tippen
        /// das nächste Zeichen an der alten Cursorposition.
        func syncNow() {
            guard let f = field else { return }
            let shown = model.engine.displayExpression(separator)
            if f.stringValue != shown { quietly { f.stringValue = shown } }
            appliedRevision = model.revision
            applySelection()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = field, let editor = f.currentEditor() else { return }
            let raw = editor.string
            let selection = editor.selectedRange
            model.userEdited(CalculatorEngine.normalized(raw), selection: selection)
            let shown = model.engine.displayExpression(separator)
            if shown != raw {
                quietly { f.stringValue = shown }
                quietly { editor.selectedRange = selection }
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                model.press(.equals)
                syncNow()
                return true
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                model.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

/// Textfeld mit eigenem Feldeditor, damit getippte Zeichen über den Rechenkern laufen.
final class CalculatorTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { CalculatorFieldCell.self }
        set { }
    }

    var calculatorEditor: CalculatorFieldEditor? { (cell as? CalculatorFieldCell)?.editor }
}

final class CalculatorFieldCell: NSTextFieldCell {
    lazy var editor: CalculatorFieldEditor = {
        let e = CalculatorFieldEditor()
        e.isFieldEditor = true
        return e
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

final class CalculatorFieldEditor: NSTextView {
    var onKey: ((CalculatorEngine.Key, NSRange) -> Void)?
    var onSelectionChange: ((NSRange) -> Void)?

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if text.count == 1, let ch = text.first, let key = CalculatorEngine.key(for: ch), let onKey {
            onKey(key, replacementRange.location == NSNotFound ? selectedRange() : replacementRange)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting, let first = ranges.first { onSelectionChange?(first.rangeValue) }
    }
}
