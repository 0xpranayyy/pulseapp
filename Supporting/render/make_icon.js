// Renders the shipping app icon to PNG at 1024, the only size the asset
// catalog needs — iOS derives the rest.
//
// The mark is the name, set in Allo Black, with the lime accent sitting in
// the e. Three earlier attempts went for a picture — a heartbeat line, a
// vector mascot, a drawn creature — and each was either the stock answer for
// "Pulse" or clip art beside the hand-illustrated icons it was meant to sit
// with. A wordmark has nothing to misread and builds the name instead.
//
// The font is embedded as a data URI rather than linked. Chromium silently
// falls back to a system face when a @font-face fails, so a linked font
// turns a wrong-font icon into something that only shows up by eye, after
// it has shipped.
//
// The lime dot is the full stop glyph, coloured — not a positioned circle.
// Placing a circle by hand looked right against the fallback face and, once
// the real metrics loaded, sat on the e like a cedilla. Letting the font set
// it means it cannot drift when the face or the size changes.
//
// The tile is square and unmasked: iOS applies its own squircle, and a
// pre-rounded PNG shows pale corners inside it.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const K = '#15161A';
const LIME = '#D9F930';
const CREAM = '#FFFBF2';
const VIOLET = '#8E5BD0';

const variants = {
  violet: { bg: VIOLET,    ink: CREAM },
  white:  { bg: '#FFFFFF', ink: K     },
  night:  { bg: '#15121C', ink: CREAM },
};

function fontFace() {
  const file = path.join(__dirname, 'fonts', 'Allo-Black.woff2');
  if (!fs.existsSync(file)) {
    throw new Error('Allo-Black.woff2 not found at ' + file +
      ' — refusing to render, the mark would silently use a fallback face.');
  }
  const b64 = fs.readFileSync(file).toString('base64');
  return `@font-face{font-family:Allo;font-weight:900;
    src:url(data:font/woff2;base64,${b64}) format('woff2');}`;
}

function page(v, px) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    ${fontFace()}
    html,body{margin:0;padding:0}
    .tile{width:${px}px;height:${px}px;background:${v.bg};position:relative}
    .mark{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
      font-family:Allo;font-weight:900;font-size:${px * 0.285}px;color:${v.ink};
      letter-spacing:${px * -0.016}px;padding-bottom:${px * 0.015}px}
    .dot{color:${LIME}}
  </style></head><body>
    <div class="tile"><div class="mark">pulse<span class="dot">.</span></div></div>
  </body></html>`;
}

(async () => {
  const out = process.argv[2] || 'AppIcon.png';
  const which = process.argv[3] || 'violet';
  const v = variants[which];
  if (!v) throw new Error('unknown variant ' + which + '; have: ' + Object.keys(variants).join(', '));

  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  await p.setContent(page(v, 1024));

  // Prove the face actually loaded. A fallback here is the whole icon wrong.
  await p.evaluate(() => document.fonts.ready);
  const loaded = await p.evaluate(() => document.fonts.check('900 300px Allo'));
  if (!loaded) { await b.close(); throw new Error('Allo did not load; refusing to write a fallback-font icon.'); }

  await p.screenshot({ path: out });
  await b.close();
  console.log('wrote ' + out + ' (' + which + ', Allo verified)');
})();
