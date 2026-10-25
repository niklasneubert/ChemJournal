// Symbole im Stil der SF Symbols der Mac-App (als SVG, damit sie unter Linux gleich aussehen).
import { html } from './lib.js';

const paths = {
  plus: '<path d="M12 5v14M5 12h14"/>',
  'plus.circle.fill': '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="M12 7.5v9M7.5 12h9" stroke="var(--panel-bg,#fff)" stroke-width="2.2"/>',
  folder: '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H9l2 2.5h7.5A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/>',
  'folder.fill': '<path fill="currentColor" stroke="none" d="M3 7.5A2.5 2.5 0 0 1 5.5 5H9l2 2.5h7.5A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/>',
  'folder.badge.plus': '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H9l2 2.5h7.5A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/><path d="M12 11v6M9 14h6"/>',
  'doc.badge.plus': '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M12 11v6M9 14h6"/>',
  'doc.text': '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>',
  'doc.on.doc': '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h2"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M5 7l1 12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2l1-12M9 7V4h6v3"/>',
  'square.and.arrow.down': '<path d="M12 3v12M7 10l5 5 5-5"/><path d="M5 15v4a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-4"/>',
  'square.and.arrow.up': '<path d="M12 15V3M7 8l5-5 5 5"/><path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6"/>',
  magnifyingglass: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  'clock.arrow.circlepath': '<path d="M3.5 12a8.5 8.5 0 1 0 2.5-6"/><path d="M3 4v4.5h4.5M12 8v4.5l3 2"/>',
  'chevron.right': '<path d="M9 5l7 7-7 7"/>',
  pencil: '<path d="M15.5 4.5l4 4L8 20H4v-4z"/>',
  'checkmark.circle.fill': '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="M7.5 12.5l3 3 6-6.5" stroke="#fff" stroke-width="2.2"/>',
  'exclamationmark.triangle.fill': '<path fill="currentColor" stroke="none" d="M12 3.2 1.8 20.5h20.4z"/><path d="M12 9.5v5M12 17.3v.2" stroke="#fff" stroke-width="2.2"/>',
  scale: '<path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/>',
  wand: '<path d="M4 20 16 8M14 6l4 4"/><path d="M18 2v3M21.5 5.5h-3M6 3v2M7 4H5M20 14v2M21 15h-2"/>',
  photo: '<rect x="3" y="4" width="18" height="16" rx="2.5"/><circle cx="9" cy="10" r="1.8"/><path d="M21 16l-5.5-5.5L5 20"/>',
  clipboard: '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V3h6v1M9 11h6M9 15h4"/>',
  xmark: '<path d="M6 6l12 12M18 6 6 18"/>',
  'xmark.circle': '<circle cx="12" cy="12" r="9.5"/><path d="M9 9l6 6M15 9l-6 6"/>',
  'pin.fill': '<path fill="currentColor" stroke="none" d="M9 3h6l-1 6 3 3v2H7v-2l3-3zM11 14h2v7h-2z"/>',
  externaldrive: '<rect x="3" y="7" width="18" height="10" rx="2.5"/><path d="M7 12h.01M17 12h-5"/>',
  'trash.slash': '<path d="M4 7h16M5 7l1 12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2l1-12M9 7V4h6v3M3 3l18 18"/>',
  flask: '<path d="M9 3h6M10 3v6L4.5 18.5A1.7 1.7 0 0 0 6 21h12a1.7 1.7 0 0 0 1.5-2.5L14 9V3"/><path d="M7 15h10"/>',
  'hand.raised': '<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V11M11 10V4.5a1.5 1.5 0 0 1 3 0V11M14 10.5V6a1.5 1.5 0 0 1 3 0v8a7 7 0 0 1-7 7h-.5A6.5 6.5 0 0 1 4 16l-1-3a1.5 1.5 0 0 1 2.7-1.3L8 15"/>',
  'textformat.subscript': '<path d="M3 5h10M8 5v13M15 17l3-3a1.4 1.4 0 0 0-2-2M15 20h4"/>',
  'arrow.up.left.and.arrow.down.right': '<path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/>',
  sync: '<path d="M4 12a8 8 0 0 1 14-5.3M20 12a8 8 0 0 1-14 5.3"/><path d="M18 3v4h-4M6 21v-4h4"/>',
};

/** <Icon name="trash" /> – Größe folgt der Schriftgröße. */
export function Icon({ name, class: cls = '' }) {
  const body = paths[name] || paths.plus;
  return html`<svg class=${'icon ' + cls} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"
    stroke-linecap="round" stroke-linejoin="round" dangerouslySetInnerHTML=${{ __html: body }}></svg>`;
}
