// Dialoge (wie macOS-Sheets/NSAlert) und Kontextmenüs.
import { html, useState, useEffect, useRef } from './lib.js';
import { Icon } from './icons.js';

// MARK: Sheet --------------------------------------------------------------------------------------------

/** Dialogfenster oben in der Mitte (wie ein macOS-Sheet). Escape = onClose. */
export function Sheet({ children, onClose, width, height, padded = true }) {
  useEffect(() => {
    const onKey = e => { if (e.key === 'Escape' && onClose) { e.stopPropagation(); onClose(); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [onClose]);
  return html`<div class="modal-backdrop" onMouseDown=${e => { if (e.target === e.currentTarget && onClose) onClose(); }}>
    <div class="modal" style=${{ width: width ? `${width}px` : undefined, height: height ? `${height}px` : undefined }}>
      ${padded ? html`<div class="modal-body">${children}</div>` : children}
    </div>
  </div>`;
}

// MARK: Alerts (Promise-basiert) ------------------------------------------------------------------------

let alertState = null;
const alertListeners = new Set();
const setAlert = s => { alertState = s; alertListeners.forEach(f => f()); };

/**
 * Zeigt eine Abfrage wie NSAlert. buttons: [{ label, role: 'default'|'cancel'|'destructive' }].
 * Ergebnis: Index des gedrückten Knopfs (Escape = Abbrechen-Knopf oder -1).
 */
export function ask({ title, message, buttons }) {
  return new Promise(resolve => setAlert({ title, message, buttons, resolve }));
}
export const alertOK = (title, message) => ask({ title, message, buttons: [{ label: 'OK', role: 'default' }] });

export function AlertHost() {
  const [, tick] = useState(0);
  useEffect(() => { const f = () => tick(t => t + 1); alertListeners.add(f); return () => alertListeners.delete(f); }, []);
  if (!alertState) return null;
  const { title, message, buttons, resolve } = alertState;
  const finish = i => { setAlert(null); resolve(i); };
  const cancelIndex = buttons.findIndex(b => b.role === 'cancel');
  const onKey = e => {
    if (e.key === 'Escape') finish(cancelIndex);
    if (e.key === 'Enter') { const d = buttons.findIndex(b => b.role === 'default'); finish(d >= 0 ? d : 0); }
  };
  return html`<div class="modal-backdrop" tabIndex="-1" onKeyDown=${onKey} ref=${el => el && el.focus()}>
    <div class="modal alert">
      <img class="app-icon" src="../../build/icon.png" alt="" />
      <div class="title">${title}</div>
      ${message && html`<div class="message">${message}</div>`}
      <div class="buttons">
        ${buttons.map((b, i) => html`<button class=${'btn ' + (b.role === 'default' ? 'primary' : b.role === 'destructive' ? 'destructive' : '')}
          onClick=${() => finish(i)}>${b.label}</button>`)}
      </div>
    </div>
  </div>`;
}

// MARK: Kontextmenü -------------------------------------------------------------------------------------

let menuState = null;
const menuListeners = new Set();
const setMenu = s => { menuState = s; menuListeners.forEach(f => f()); };

/**
 * Öffnet ein Kontextmenü an der Mausposition. items: [{ label, icon, action, destructive } | 'separator'].
 * Verwendung: onContextMenu=${e => openContextMenu(e, [...])}
 */
export function openContextMenu(event, items) {
  event.preventDefault();
  event.stopPropagation();
  setMenu({ x: event.clientX, y: event.clientY, items });
}

export function ContextMenuHost() {
  const [, tick] = useState(0);
  const ref = useRef(null);
  useEffect(() => { const f = () => tick(t => t + 1); menuListeners.add(f); return () => menuListeners.delete(f); }, []);
  useEffect(() => {
    if (!menuState) return undefined;
    const close = () => setMenu(null);
    const onKey = e => { if (e.key === 'Escape') close(); };
    window.addEventListener('mousedown', close);
    window.addEventListener('blur', close);
    window.addEventListener('keydown', onKey);
    // Menü im Fenster halten
    const el = ref.current;
    if (el) {
      const r = el.getBoundingClientRect();
      if (r.right > window.innerWidth) el.style.left = `${Math.max(4, window.innerWidth - r.width - 4)}px`;
      if (r.bottom > window.innerHeight) el.style.top = `${Math.max(4, window.innerHeight - r.height - 4)}px`;
    }
    return () => { window.removeEventListener('mousedown', close); window.removeEventListener('blur', close); window.removeEventListener('keydown', onKey); };
  });
  if (!menuState) return null;
  return html`<div class="context-menu" ref=${ref} style=${{ left: `${menuState.x}px`, top: `${menuState.y}px` }} onMouseDown=${e => e.stopPropagation()}>
    ${menuState.items.map(item => (item === 'separator'
      ? html`<div class="sep"></div>`
      : html`<div class=${'item' + (item.destructive ? ' destructive' : '')} onClick=${() => { setMenu(null); item.action(); }}>
          ${item.icon ? html`<${Icon} name=${item.icon} />` : html`<span style="width:1em"></span>`}<span>${item.label}</span>
        </div>`))}
  </div>`;
}

/** Klappmenü an einem Knopf (z. B. „+“ in der Seitenleiste). */
export function openMenuAt(element, items) {
  const r = element.getBoundingClientRect();
  setMenu({ x: r.left, y: r.bottom + 4, items });
}
