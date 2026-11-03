// Taschenrechner – gleiche Fälle wie CalculatorTests.swift der Mac-App.
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { Calculator: C } = require('../src/shared/calculator');

/** Tippt eine Folge wie auf der Tastatur ein ("12.5*3="). */
function typed(keys) {
  const c = new C.Calculator();
  for (const ch of keys) { const k = C.keyFor(ch); if (k) c.press(k); }
  return c;
}

test('Taschenrechner: Punkt vor Strich, Klammern, Potenz, Wurzel, Prozent', () => {
  assert.strictEqual(C.evaluate('2+3×4'), 14);
  assert.strictEqual(C.evaluate('(2+3)×4'), 20);
  assert.strictEqual(C.evaluate('10÷4'), 2.5);
  assert.strictEqual(C.evaluate('2^3^2'), 512);
  assert.strictEqual(C.evaluate('−2²'), -4);
  assert.strictEqual(C.evaluate('√(16)+1'), 5);
  assert.strictEqual(C.evaluate('50%×80'), 40);
  assert.strictEqual(C.evaluate('3−−2'), 5);
  assert.strictEqual(C.evaluate('1÷0'), null);
  assert.strictEqual(C.evaluate('√(−4)'), null);
  assert.strictEqual(C.evaluate('2+'), null);
});

test('Taschenrechner: Eingabe wie auf der Tastatur; nach „=“ bleibt die Aufgabe stehen', () => {
  const c = typed('12.5*3=');
  assert.strictEqual(c.expression, '12.5×3');
  assert.ok(c.result === 37.5 && c.showsResult);
  c.press('add'); c.press('2');
  assert.strictEqual(c.expression, '37.5+2');
  c.press('equals');
  assert.strictEqual(c.result, 39.5);
  c.press('7');
  assert.strictEqual(c.expression, '7');
  assert.strictEqual(typed('8+*2=').result, 16);
  assert.strictEqual(typed('1,5+1,5=').result, 3);
  assert.strictEqual(typed('0.1+0.2+=').expression, '0.1+0.2');
  assert.strictEqual(typed('2(3+4=').expression, '2×(3+4)');
  assert.strictEqual(typed('2(3+4=').result, 14);
  assert.strictEqual(typed('6*7+').currentValue, 42);
  assert.ok(typed('6/0=').hasError);
  assert.strictEqual(typed('6/0=7').expression, '7');
  const d = typed('0.1+0.2=');
  d.press('multiply'); d.press('3');
  assert.strictEqual(d.expression, '0.3×3');
});

test('Taschenrechner: Aufgabe nach „=“ bearbeiten – Cursor, Einfügen, Löschen', () => {
  const c = typed('12+3=');
  const e = typed('12+3=');
  e.press('backspace');
  assert.ok(e.expression === '12+' && !e.showsResult);
  let pos = c.pressAt('5', 2);
  assert.ok(c.expression === '125+3' && pos === 3 && !c.showsResult);
  assert.strictEqual(c.currentValue, 128);
  pos = c.pressAt('backspace', 1);
  assert.ok(c.expression === '25+3' && pos === 0);
  c.pressAt('multiply', 2);
  assert.strictEqual(c.expression, '25×+3');
  const w = new C.Calculator('2×√(9)');
  pos = w.pressAt('backspace', 4);
  assert.ok(w.expression === '2×9)' && pos === 2);
  const h = typed('1+1=');
  h.setExpression(C.normalized('3*4-1'));
  assert.ok(h.expression === '3×4−1' && h.currentValue === 11 && !h.showsResult);
  assert.strictEqual(C.normalized('2,5/5'), '2.5÷5');
});

test('Taschenrechner: Vorzeichen, Löschen, Rücktaste', () => {
  const c = typed('5+3');
  c.press('negate'); assert.strictEqual(c.expression, '5+−3');
  c.press('negate'); assert.strictEqual(c.expression, '5+3');
  c.press('backspace'); assert.strictEqual(c.expression, '5+');
  c.press('clear'); assert.strictEqual(c.expression, '');
  const r = typed('4='); r.press('negate'); assert.strictEqual(r.expression, '−4');
  const w = typed('16='); w.press('squareRoot');
  assert.strictEqual(w.expression, '√(16)');
  assert.strictEqual(w.currentValue, 4);
});

test('Taschenrechner: Anzeige mit Punkt oder Komma', () => {
  assert.strictEqual(C.format(1234.5, '.'), '1234.5');
  assert.strictEqual(C.format(1234.5, ','), '1234,5');
  assert.strictEqual(C.format(0.1 + 0.2, '.'), '0.3');
  assert.strictEqual(C.format(1.5e-9, ','), '1,5e-9');
  assert.strictEqual(C.format(2e12, '.'), '2e12');
  assert.strictEqual(C.format(-0, '.'), '0');
  assert.strictEqual(C.format(-42.25, '.'), '-42.25');
  assert.strictEqual(typed('2.5*2').display(','), '2,5×2');
});
