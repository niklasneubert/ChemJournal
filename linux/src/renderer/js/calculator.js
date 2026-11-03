// Taschenrechner in der Symbolleiste – entspricht Views/CalculatorView.swift der Mac-App.
// Öffnet sich als Popover unter dem Knopf. Am Rand gezogen, löst er sich und schwebt frei im Fenster (mit Titelleiste
// und Schließen-Knopf), bis man ihn schließt. Die Rechnung bleibt beim Schließen und Wiederöffnen erhalten.
import { html, CJ, t, useState, useEffect, useRef, useLayoutEffect, stored } from './lib.js';
import { Icon } from './icons.js';

const C = () => CJ.Calculator;

// MARK: Zustand (gemeinsam für Popover und schwebendes Fenster)

const state = {
  calc: null,
  selection: { start: 0, end: 0 },   // Cursor/Auswahl im Rechenfeld
  revision: 0,                         // erhöht bei Änderungen über die Tasten: Feld übernimmt Text und Cursor
  mode: null,                          // null | 'popover' | 'floating'
  anchor: null,                        // Rechteck des Knopfs (Popover)
  pos: { x: 0, y: 0 },                 // Lage des Fensters
};
const listeners = new Set();
const notify = () => listeners.forEach(f => f());
const calc = () => (state.calc ||= new (C().Calculator)());
export const SEPARATOR_EVENT = 'cj-calculator-separator';
const separator = () => (stored(C().SEPARATOR_KEY, '.') === ',' ? ',' : '.');

/** Taste an der Cursorposition; eine Auswahl wird ersetzt. */
function press(key) {
  const c = calc();
  const n = c.expression.length;
  let { start, end } = state.selection;
  start = Math.min(Math.max(start, 0), n); end = Math.min(Math.max(end, start), n);
  let cursor;
  if (end > start && key !== 'equals' && key !== 'clear') {
    c.setExpression(c.expression.slice(0, start) + c.expression.slice(end));
    cursor = key === 'backspace' ? start : c.pressAt(key, start);
  } else cursor = c.pressAt(key, start);
  state.selection = { start: cursor, end: cursor };
  state.revision++;
  notify();
}

function close() { state.mode = null; notify(); }

/** Knopf in der Symbolleiste. */
export function CalculatorButton() {
  const open = e => {
    if (state.mode === 'floating') { state.revision++; notify(); return; }   // holt den Fokus ins Rechenfeld
    if (state.mode === 'popover') { close(); return; }
    const r = e.currentTarget.getBoundingClientRect();
    state.anchor = { left: r.left, bottom: r.bottom, center: r.left + r.width / 2 };
    state.mode = 'popover';
    state.selection = { start: calc().expression.length, end: calc().expression.length };
    state.revision++;
    notify();
  };
  return html`<button class="toolbar-button" data-calculator-button="1" title=${t('Taschenrechner – am Rand wegziehen, um ihn frei schweben zu lassen')}
    onClick=${open}><${Icon} name="action.calculator" /></button>`;
}

/** Wird einmal im Fenster eingebunden (wie das Kontextmenü). */
export function CalculatorHost() {
  const [, tick] = useState(0);
  useEffect(() => {
    const f = () => tick(x => x + 1);
    listeners.add(f);
    window.addEventListener(SEPARATOR_EVENT, f);
    return () => { listeners.delete(f); window.removeEventListener(SEPARATOR_EVENT, f); };
  }, []);
  if (!state.mode) return null;
  return html`<${CalculatorPanel} mode=${state.mode} />`;
}

const PANEL_WIDTH = 276;

function CalculatorPanel({ mode }) {
  const ref = useRef(null);
  const fieldRef = useRef(null);
  const [copied, setCopied] = useState(false);
  const sep = separator();
  const c = calc();

  // Popover: unter dem Knopf, im Fenster gehalten
  if (mode === 'popover' && state.anchor) {
    state.pos = {
      x: Math.max(8, Math.min(window.innerWidth - PANEL_WIDTH - 8, state.anchor.center - 28)),
      y: state.anchor.bottom + 8,
    };
  }

  // Popover schließt bei Klick daneben (nicht beim schwebenden Fenster)
  useEffect(() => {
    if (mode !== 'popover') return undefined;
    const down = e => {
      if (ref.current && ref.current.contains(e.target)) return;
      if (e.target.closest && e.target.closest('[data-calculator-button]')) return;
      close();
    };
    window.addEventListener('mousedown', down);
    return () => window.removeEventListener('mousedown', down);
  }, [mode]);

  // Im Fenster halten, wenn es kleiner wird
  useEffect(() => {
    const fit = () => {
      const el = ref.current; if (!el) return;
      const h = el.offsetHeight;
      state.pos = { x: Math.max(0, Math.min(state.pos.x, window.innerWidth - PANEL_WIDTH)), y: Math.max(0, Math.min(state.pos.y, window.innerHeight - h)) };
      el.style.left = `${state.pos.x}px`; el.style.top = `${state.pos.y}px`;
    };
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, []);

  // Feld übernimmt Text und Cursor nach Tastendruck/Öffnen
  useLayoutEffect(() => {
    const f = fieldRef.current; if (!f) return;
    const text = c.display(sep);
    if (f.value !== text) f.value = text;
    if (document.activeElement !== f) f.focus({ preventScroll: true });
    const { start, end } = state.selection;
    f.setSelectionRange(Math.min(start, text.length), Math.min(end, text.length));
  }, [state.revision, mode, sep]);

  const recordSelection = () => {
    const f = fieldRef.current;
    if (f && document.activeElement === f) state.selection = { start: f.selectionStart, end: f.selectionEnd };
  };

  const onKeyDown = e => {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.key === 'Enter') { e.preventDefault(); recordSelection(); press('equals'); return; }
    if (e.key === 'Escape') { e.preventDefault(); if (mode === 'popover') close(); return; }
    if (e.key.length === 1) {
      e.preventDefault();   // Buchstaben u. Ä. gar nicht erst ins Feld lassen
      const k = C().keyFor(e.key);
      if (k) { recordSelection(); press(k); }
    }
  };
  // Löschen, Einfügen, Ausschneiden: Text übernehmen
  const onInput = e => {
    const f = e.target;
    const internal = C().normalized(f.value);
    c.setExpression(internal);
    state.selection = { start: f.selectionStart, end: f.selectionEnd };
    const shown = c.display(sep);
    if (shown !== f.value) { const s = f.selectionStart; f.value = shown; f.setSelectionRange(s, s); }
    notify();
  };

  // Ziehen am Rand (nicht an Knöpfen oder am Feld): Popover löst sich, schwebendes Fenster wandert
  const onPointerDown = e => {
    if (e.button !== 0 || e.target.closest('button, input')) return;
    e.preventDefault();
    const el = ref.current;
    const startX = e.clientX, startY = e.clientY, from = { ...state.pos };
    let moved = false;
    el.setPointerCapture(e.pointerId);
    const move = ev => {
      const dx = ev.clientX - startX, dy = ev.clientY - startY;
      if (!moved && Math.hypot(dx, dy) < 5) return;
      moved = true;
      if (state.mode === 'popover') { state.mode = 'floating'; notify(); }
      state.pos = {
        x: Math.max(0, Math.min(window.innerWidth - PANEL_WIDTH, from.x + dx)),
        y: Math.max(0, Math.min(window.innerHeight - 40, from.y + dy)),
      };
      el.style.left = `${state.pos.x}px`; el.style.top = `${state.pos.y}px`;
    };
    const up = () => {
      el.removeEventListener('pointermove', move); el.removeEventListener('pointerup', up); el.removeEventListener('pointercancel', up);
      fieldRef.current && fieldRef.current.focus({ preventScroll: true });
    };
    el.addEventListener('pointermove', move); el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up);
  };

  const value = c.hasError ? null : c.showsResult ? c.result : c.currentValue;
  const resultText = c.hasError ? t('Fehler') : value !== null ? C().format(value, sep) : (c.expression ? ' ' : '0');
  const copy = () => { if (value === null) return; navigator.clipboard.writeText(C().format(value, sep)); setCopied(true); };

  // Tasten: mousedown verhindern, damit der Fokus (und der Cursor) im Rechenfeld bleibt
  const key = (label, k, style, help) => html`<button class=${'calc-key ' + style} title=${help || ''}
    onMouseDown=${e => { e.preventDefault(); recordSelection(); }} onClick=${() => { press(k); setCopied(false); }}>${label}</button>`;

  return html`<div ref=${ref} class=${'calc-panel ' + mode} style=${{ left: `${state.pos.x}px`, top: `${state.pos.y}px` }} onPointerDown=${onPointerDown}>
    ${mode === 'floating' && html`<div class="calc-titlebar">
      <button class="calc-close" title=${t('Schließen')} onClick=${close}><${Icon} name="xmark" /></button>
      <span>${t('Taschenrechner')}</span><span class="calc-close-spacer"></span>
    </div>`}
    <div class="calc-body">
      <div class="calc-display">
        <div class="calc-line">
          <button class="icon-button gray calc-copy" title=${t('Ergebnis kopieren')} disabled=${value === null} onClick=${copy}>
            <${Icon} name=${copied ? 'checkmark' : 'doc.on.doc'} /></button>
          <input ref=${fieldRef} class="calc-field" placeholder="0" spellcheck="false" autocomplete="off"
            onKeyDown=${onKeyDown} onInput=${onInput} onSelect=${recordSelection} onKeyUp=${recordSelection} onMouseUp=${recordSelection} />
        </div>
        <div class=${'calc-result' + (c.hasError ? ' error' : c.showsResult ? ' final' : '')}>${resultText}</div>
      </div>
      <div class="calc-keys">
        ${key('√', 'squareRoot', 'function', t('Wurzel'))}${key(html`x<sup>y</sup>`, 'power', 'function', t('Potenz (^)'))}
        ${key('%', 'percent', 'function', t('Prozent'))}${key('⌫', 'backspace', 'function', t('Letztes Zeichen löschen'))}
        ${key('C', 'clear', 'function', t('Zurücksetzen (C)'))}${key('(', 'openParen', 'function')}${key(')', 'closeParen', 'function')}${key('÷', 'divide', 'operator')}
        ${key('7', '7', 'digit')}${key('8', '8', 'digit')}${key('9', '9', 'digit')}${key('×', 'multiply', 'operator')}
        ${key('4', '4', 'digit')}${key('5', '5', 'digit')}${key('6', '6', 'digit')}${key('−', 'subtract', 'operator')}
        ${key('1', '1', 'digit')}${key('2', '2', 'digit')}${key('3', '3', 'digit')}${key('+', 'add', 'operator')}
        ${key('±', 'negate', 'function', t('Vorzeichen wechseln'))}${key('0', '0', 'digit')}
        ${key(sep, 'decimal', 'digit', t('Dezimaltrennzeichen – in den Einstellungen wählbar'))}${key('=', 'equals', 'equals')}
      </div>
    </div>
  </div>`;
}
