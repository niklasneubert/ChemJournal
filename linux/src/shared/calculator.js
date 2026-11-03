// Rechenkern des Taschenrechners – entspricht Utilities/CalculatorEngine.swift der Mac-App.
//
// Die Eingabe wird als Ausdruck gesammelt (intern immer mit „.“ als Dezimalzeichen), z. B. „12.5×(3+4)“, und mit
// Punkt-vor-Strich ausgewertet: + − × ÷, Klammern, Potenz (^, ²), Wurzel (√), Prozent (%), Vorzeichenwechsel.
// Nach „=“ bleibt die gerechnete Aufgabe stehen und kann bearbeitet werden.
(function (g) {
  'use strict';
  const node = typeof module === 'object' && module.exports;

  const SEPARATOR_KEY = 'calculator.decimalSeparator';
  const OPERATORS = new Set(['+', '−', '×', '÷', '^']);
  const isDigit = c => c >= '0' && c <= '9' && c.length === 1;
  const isOperator = c => c !== undefined && OPERATORS.has(c);
  const last = s => (s.length ? s[s.length - 1] : undefined);
  const openParens = s => Math.max(0, [...s].filter(c => c === '(').length - [...s].filter(c => c === ')').length);

  /** Zahl mit bis zu 10 gültigen Stellen (wie printf „%.10g“): 0.1+0.2 → „0.3“, 1.5e-9 → „1.5e-9“, 2e12 → „2e12“. */
  function format(value, separator = '.') {
    if (!Number.isFinite(value)) return '–';
    if (value === 0) value = 0;   // keine „-0“
    const [mant, expText] = value.toExponential(9).split('e');
    const exp = Number(expText);
    let text;
    if (exp < -4 || exp >= 10) {
      text = mant.replace(/\.?0+$/, '') + 'e' + exp;
    } else {
      text = value.toFixed(Math.max(0, 9 - exp));
      if (text.includes('.')) text = text.replace(/\.?0+$/, '');
    }
    return separator === '.' ? text : text.replace(/\./g, ',');
  }

  /** Ergebnis als Zahl zum Weiterrechnen (intern, ohne Exponent). */
  function resultText(value) {
    const text = format(value, '.');
    if (!text.includes('e')) return text.replace('-', '−');
    const plain = Math.abs(value).toLocaleString('en-US', { useGrouping: false, maximumSignificantDigits: 10 });
    return (value < 0 ? '−' : '') + plain;
  }

  /** Taste zu einem getippten Zeichen; Punkt und Komma gelten beide als Dezimalzeichen. */
  function keyFor(ch) {
    if (isDigit(ch)) return ch;
    switch (ch) {
      case '.': case ',': return 'decimal';
      case '+': return 'add';
      case '-': case '−': return 'subtract';
      case '*': case '×': case 'x': case 'X': return 'multiply';
      case '/': case '÷': case ':': return 'divide';
      case '^': return 'power';
      case '(': return 'openParen';
      case ')': return 'closeParen';
      case '%': return 'percent';
      case '²': return 'square';
      case '=': return 'equals';
      case 'c': case 'C': return 'clear';
      default: return null;
    }
  }

  /** Eingabe in die interne Schreibweise: * → ×, / → ÷, - → −, Komma → Punkt. */
  function normalized(text) {
    return [...String(text)].map(ch => ({ '*': '×', x: '×', X: '×', '/': '÷', ':': '÷', '-': '−', ',': '.' }[ch] || ch)).join('');
  }

  // MARK: Auswertung (rekursiver Abstieg) – null bei Syntaxfehler, Division durch 0, Wurzel aus negativer Zahl
  function evaluate(text) {
    const chars = [...text];
    let pos = 0;
    const peek = () => chars[pos];
    function sum() {
      let v = product(); if (v === null) return null;
      while (peek() === '+' || peek() === '−') {
        const op = chars[pos++]; const r = product(); if (r === null) return null;
        v = op === '+' ? v + r : v - r;
      }
      return v;
    }
    function product() {
      let v = unary(); if (v === null) return null;
      while (peek() === '×' || peek() === '÷') {
        const op = chars[pos++]; const r = unary(); if (r === null) return null;
        if (op === '÷') { if (r === 0) return null; v /= r; } else v *= r;
      }
      return v;
    }
    function unary() {   // Vorzeichen bindet schwächer als die Potenz: −2² = −4
      if (peek() === '−') { pos++; const v = unary(); return v === null ? null : -v; }
      if (peek() === '+') { pos++; return unary(); }
      return power();
    }
    function power() {
      const base = postfix(); if (base === null) return null;
      if (peek() === '^') {
        pos++; const e = unary(); if (e === null) return null;   // rechtsassoziativ
        const v = Math.pow(base, e); return Number.isFinite(v) ? v : null;
      }
      return base;
    }
    function postfix() {
      let v = atom(); if (v === null) return null;
      while (peek() === '%' || peek() === '²') { v = chars[pos++] === '%' ? v / 100 : v * v; }
      return v;
    }
    function atom() {
      const c = peek();
      if (c === undefined) return null;
      if (c === '(') { pos++; const v = sum(); if (v === null || peek() !== ')') return null; pos++; return v; }
      if (c === '√') { pos++; const v = atom(); if (v === null || v < 0) return null; return Math.sqrt(v); }
      let t = '';
      while (peek() !== undefined && (isDigit(peek()) || peek() === '.')) t += chars[pos++];
      if (!t || (t.match(/\./g) || []).length > 1 || t === '.') return null;
      return Number(t);
    }
    const v = sum();
    return v !== null && pos === chars.length && Number.isFinite(v) ? v : null;
  }

  class Calculator {
    constructor(expression = '') {
      this.expression = expression;
      this.result = null;
      this.showsResult = false;
      this.hasError = false;
    }

    get currentValue() {
      let text = this.expression;
      while (text && (isOperator(last(text)) || last(text) === '(' || last(text) === '√')) text = text.slice(0, -1);
      if (!text) return null;
      return evaluate(text + ')'.repeat(openParens(text)));
    }

    display(separator = '.') { return separator === '.' ? this.expression : this.expression.replace(/\./g, ','); }

    get _closing() { return [')', '%', '²'].includes(last(this.expression)); }
    get _currentNumber() { const m = /[0-9.]*$/.exec(this.expression); return m ? m[0] : ''; }
    _needsTimes() { const l = last(this.expression); return this._closing || (l !== undefined && isDigit(l)) || l === '.'; }

    /** Taste am Ende des Ausdrucks. */
    press(key) {
      if (this.showsResult) {
        if (key === 'equals') return;
        const previous = this.hasError || this.result === null ? null : resultText(this.result);
        this.showsResult = false; this.hasError = false; this.result = null;
        if (key === 'clear' || key === 'backspace') { /* ⌫ bearbeitet die gerechnete Aufgabe */ }
        else if (isDigit(key) || key === 'decimal' || key === 'openParen') this.expression = '';
        else if (key === 'squareRoot') { this.expression = previous === null ? '' : `√(${previous})`; return; }
        else this.expression = previous === null ? '' : previous;   // Rechenzeichen: mit dem Ergebnis weiterrechnen
      }
      const e = () => this.expression;
      if (isDigit(key)) { if (this._closing) this.expression += '×'; this.expression += key; return; }
      switch (key) {
        case 'decimal':
          if (this._currentNumber.includes('.')) return;
          if (this._closing) this.expression += '×';
          this.expression += this._currentNumber ? '.' : '0.';
          return;
        case 'add': return this._operator('+');
        case 'subtract':
          // Am Anfang oder nach „(“ / einem Rechenzeichen ist − ein Vorzeichen
          if (!e() || last(e()) === '(' || isOperator(last(e()))) { if (last(e()) !== '−') this.expression += '−'; }
          else this._operator('−');
          return;
        case 'multiply': return this._operator('×');
        case 'divide': return this._operator('÷');
        case 'power': return this._operator('^');
        case 'openParen': if (this._needsTimes()) this.expression += '×'; this.expression += '('; return;
        case 'closeParen': {
          const l = last(e());
          if (openParens(e()) > 0 && l !== undefined && l !== '(' && !isOperator(l)) this.expression += ')';
          return;
        }
        case 'percent': return this._postfix('%');
        case 'square': return this._postfix('²');
        case 'squareRoot': if (this._needsTimes()) this.expression += '×'; this.expression += '√('; return;
        case 'negate': return this._negate();
        case 'equals': return this._evaluate();
        case 'clear': this.expression = ''; return;
        case 'backspace':
          if (e().endsWith('√(')) this.expression = e().slice(0, -2);
          else this.expression = e().slice(0, -1);
          return;
        default: return;
      }
    }

    /** Taste an einer Cursorposition; gibt die neue Cursorposition zurück. Mitten im Ausdruck wird eingefügt bzw.
     *  vor dem Cursor gelöscht – auch in einer gerechneten Aufgabe. */
    pressAt(key, cursor) {
      const n = this.expression.length;
      const c = Math.min(Math.max(cursor, 0), n);
      if (c === n || key === 'equals' || key === 'clear') { this.press(key); return this.expression.length; }
      this.showsResult = false; this.hasError = false; this.result = null;
      if (key === 'backspace') {
        if (c === 0) return 0;
        const width = c >= 2 && this.expression.slice(c - 2, c) === '√(' ? 2 : 1;
        this.expression = this.expression.slice(0, c - width) + this.expression.slice(c);
        return c - width;
      }
      const head = new Calculator(this.expression.slice(0, c));
      head.press(key);
      this.expression = head.expression + this.expression.slice(c);
      return head.expression.length;
    }

    /** Ausdruck von Hand bearbeitet (Textfeld). */
    setExpression(text) {
      if (text === this.expression && !this.showsResult) return;
      this.expression = text;
      this.showsResult = false; this.hasError = false; this.result = null;
    }

    _operator(op) {
      if (!this.expression) this.expression = '0';
      if (last(this.expression) === '(') return;
      if (last(this.expression) === '.') this.expression = this.expression.slice(0, -1);
      while (isOperator(last(this.expression))) this.expression = this.expression.slice(0, -1);   // ersetzen statt verdoppeln
      if (!this.expression) this.expression = '0';
      this.expression += op;
    }

    _postfix(ch) {
      const l = last(this.expression);
      if (l === undefined || !(isDigit(l) || [')', '%', '²', '.'].includes(l))) return;
      if (l === '.') this.expression = this.expression.slice(0, -1);
      this.expression += ch;
    }

    /** ± : Vorzeichen der letzten Zahl (bzw. Klammer) umschalten. */
    _negate() {
      const e = this.expression;
      if (!e) { this.expression = '−'; return; }
      if (e === '−') { this.expression = ''; return; }
      let start = e.length - this._currentNumber.length;
      if (start === e.length && last(e) === ')') {
        let depth = 0, i = e.length;
        while (i > 0) { i--; if (e[i] === ')') depth++; else if (e[i] === '(') { depth--; if (depth === 0) break; } }
        start = i;
        if (start > 0 && e[start - 1] === '√') start--;
      }
      if (start > 0) {
        const before = start - 1;
        const unary = e[before] === '−' && (before === 0 || isOperator(e[before - 1]) || e[before - 1] === '(');
        if (unary) { this.expression = e.slice(0, before) + e.slice(start); return; }
      }
      this.expression = e.slice(0, start) + '−' + e.slice(start);
    }

    _evaluate() {
      let text = this.expression;
      while (text && (isOperator(last(text)) || ['(', '√', '.'].includes(last(text)))) text = text.slice(0, -1);
      if (!text) return;
      text += ')'.repeat(openParens(text));
      this.expression = text;
      this.showsResult = true;
      const v = evaluate(text);
      if (v === null) this.hasError = true; else this.result = v;
    }
  }

  const api = { Calculator: { Calculator, evaluate, format, keyFor, normalized, SEPARATOR_KEY } };
  if (node) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
