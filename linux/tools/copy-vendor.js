// Kopiert die benötigten Bibliotheken nach src/renderer/vendor (nach "npm install" einmal ausführen).
// MathJax kommt aus dem Mac-Projekt (gleiche Datei wie in der Mac-App).
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const vendor = path.join(root, 'src/renderer/vendor');
const nm = path.join(root, 'node_modules');
fs.mkdirSync(vendor, { recursive: true });
const files = [
  [path.join(nm, 'preact/dist/preact.module.js'), 'preact.module.js'],
  [path.join(nm, 'preact/hooks/dist/hooks.module.js'), 'hooks.module.js'],
  [path.join(nm, 'htm/dist/htm.module.js'), 'htm.module.js'],
  [path.join(nm, 'pdfjs-dist/build/pdf.min.mjs'), 'pdf.min.mjs'],
  [path.join(nm, 'pdfjs-dist/build/pdf.worker.min.mjs'), 'pdf.worker.min.mjs'],
  [path.join(root, '../macos/ChemJournal/Resources/MathJax/mathjax-tex-svg-full.js'), 'mathjax-tex-svg-full.js'],
  [path.join(root, '../macos/ChemJournal/Resources/MathJax/MathJax-LICENSE.txt'), 'MathJax-LICENSE.txt'],
];
for (const [from, to] of files) {
  fs.copyFileSync(from, path.join(vendor, to));
  console.log('kopiert:', to);
}
// Ohne Build-Schritt gibt es keine "bare imports": Hooks direkt auf die Preact-Datei verweisen lassen
const hooks = path.join(vendor, 'hooks.module.js');
fs.writeFileSync(hooks, fs.readFileSync(hooks, 'utf8').replace(/from\s*"preact"/g, 'from"./preact.module.js"'));
