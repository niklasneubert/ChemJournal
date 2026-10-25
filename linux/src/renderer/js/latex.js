// Textfeld mit automatischer Formel-Vorschau – entspricht Views/LaTeXEditorView.swift.
// - Im Feld: LaTeX-Quelltext bearbeiten ($…$, \ce{…}).
// - Feld verlassen: Formeln werden gesetzt; erst wenn das fertig ist, blendet die Vorschau weich ein.
// - Klick auf die Vorschau: zurück in den Quelltext, Cursor sofort im Feld.
// - Text ohne Formeln bleibt einfach als Text stehen.
import { html, CJ, useState, useEffect, useRef, useLayoutEffect } from './lib.js';

let mathJaxReady = null;
function whenMathJaxReady() {
  if (!mathJaxReady) {
    mathJaxReady = new Promise(resolve => {
      const wait = () => (window.MathJax && MathJax.startup && MathJax.startup.promise ? MathJax.startup.promise.then(resolve) : setTimeout(wait, 30));
      wait();
    });
  }
  return mathJaxReady;
}

let queue = Promise.resolve();
/** Setzt Formeln abseits des Sichtbereichs und liefert das fertige HTML. */
export function typeset(text) {
  const job = queue.then(async () => {
    await whenMathJaxReady();
    const stage = document.createElement('div');
    stage.style.cssText = 'position:absolute;left:-10000px;top:0;visibility:hidden;';
    stage.innerHTML = CJ.previewHTML(text);
    document.body.appendChild(stage);
    try {
      MathJax.typesetClear();
      await MathJax.typesetPromise([stage]);
    } catch (e) { /* Text bleibt ungesetzt */ }
    const out = stage.innerHTML;
    stage.remove();
    return out;
  });
  queue = job.catch(() => {});
  return job;
}

export function LaTeXEditor({ title, value, onChange, onContextMenu }) {
  const [focused, setFocused] = useState(false);
  const [editing, setEditing] = useState(false);
  const [rendered, setRendered] = useState(null);   // { text, html }
  const ref = useRef(null);
  const hasFormulas = CJ.containsFormulas(value);
  const showPreview = !focused && !editing && hasFormulas && rendered && rendered.text === value;

  // Beim Verlassen (und beim ersten Anzeigen) im Hintergrund setzen
  useEffect(() => {
    if (focused || !hasFormulas || (rendered && rendered.text === value)) return undefined;
    let cancelled = false;
    typeset(value).then(out => { if (!cancelled) setRendered({ text: value, html: out }); });
    return () => { cancelled = true; };
  }, [focused, value, hasFormulas]);

  // Höhe an den Inhalt anpassen
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el || showPreview) return;
    el.style.height = 'auto';
    el.style.height = `${Math.max(80, el.scrollHeight)}px`;
  });

  useEffect(() => { if (editing && ref.current) { ref.current.focus(); } }, [editing]);

  return html`<div>
    <div class="section-head"><span class="headline">${title}</span></div>
    <div class=${'text-area-box' + (focused ? ' focused' : '')} onContextMenu=${onContextMenu}>
      ${showPreview
        ? html`<div class="formula-preview" title="Zum Bearbeiten klicken" onClick=${() => setEditing(true)}
            dangerouslySetInnerHTML=${{ __html: rendered.html }}></div>`
        : html`<textarea ref=${ref} class="text-area" value=${value} spellcheck="true"
            onInput=${e => onChange(e.target.value)}
            onFocus=${() => setFocused(true)}
            onBlur=${() => { setFocused(false); setEditing(false); }}></textarea>`}
    </div>
  </div>`;
}

/** Schreibgeschützte Anzeige mit gesetzten Formeln (Verlauf, Gelöschte Ansätze). */
export function RichText({ text, class: cls = '' }) {
  const [out, setOut] = useState(null);
  useEffect(() => {
    let cancelled = false;
    if (!CJ.containsFormulas(text)) { setOut(null); return undefined; }
    typeset(text).then(r => { if (!cancelled) setOut(r); });
    return () => { cancelled = true; };
  }, [text]);
  if (out) return html`<div class=${cls} dangerouslySetInnerHTML=${{ __html: out }}></div>`;
  return html`<div class=${cls} style="white-space: pre-wrap">${text}</div>`;
}
