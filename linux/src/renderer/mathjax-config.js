// MathJax-Einstellungen wie in der Mac-App: $…$ inline, $$…$$ abgesetzt, \ce{…} über mhchem.
// fontCache 'none': jede Formel ist in sich vollständig und kann in die Vorschau kopiert werden.
window.MathJax = {
  tex: { inlineMath: [['$', '$']], displayMath: [['$$', '$$']], packages: { '[+]': ['mhchem'] } },
  svg: { fontCache: 'none' },
  startup: { typeset: false },
};
