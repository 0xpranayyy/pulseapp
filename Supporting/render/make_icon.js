// Renders the shipping app icon to PNG at 1024, the only size the asset
// catalog needs — iOS derives the rest.
//
// The mark is Pip peeking up over the meadow under a blue sky, with the sun
// in the corner: the brand sheet's icon tile, drawn as vector here so it is
// crisp at 1024 and matches the in-app Pip exactly (same palette, same eye
// and antenna geometry). It replaces the "pulse." wordmark, which was set in
// Allo — no longer bundled — and said less than the mascot does.
//
// Pure SVG, no fonts, so there is no fallback-face failure mode to guard.
//
// The tile is square and unmasked: iOS applies its own squircle, and a
// pre-rounded PNG shows pale corners inside it.
//
//   node make_icon.js [out.png]
const { chromium } = require('playwright');

const SKY_TOP = '#46B7F0';
const SKY_BOTTOM = '#C6EDFF';
const SUN = '#FFD23F';
const SUN_CORE = '#FFE369';
const HILL_FAR = '#9BDB6C';
const MEADOW = '#4DAE2C';
const MEADOW_SHADE = '#3A9A22';
const PIP_BODY = '#FFB3C7';
const PIP_LIGHT = '#FFD3DE';
const PIP_FOOT = '#F598B2';
const PIP_LINE = '#E2789A';
const BLUSH = '#FF8FAE';
const INK = '#1F2557';
const LIME = '#D9F930';

const rays = [0, 72, 144, 216, 288]
  .map(a => `<rect x="-3" y="-28" width="6" height="9" rx="3" fill="${SUN}" transform="rotate(${a})"/>`)
  .join('');

const svg = (px) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="0 0 220 220">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${SKY_TOP}"/><stop offset="1" stop-color="${SKY_BOTTOM}"/>
    </linearGradient>
    <radialGradient id="body" cx="38%" cy="22%" r="80%">
      <stop offset="0" stop-color="${PIP_LIGHT}"/>
      <stop offset="0.55" stop-color="${PIP_BODY}"/>
      <stop offset="1" stop-color="${PIP_FOOT}"/>
    </radialGradient>
    <radialGradient id="orb" cx="35%" cy="30%" r="70%">
      <stop offset="0" stop-color="#F6FFB2"/><stop offset="1" stop-color="#C2E21C"/>
    </radialGradient>
  </defs>
  <rect x="0" y="0" width="220" height="220" fill="url(#sky)"/>
  <g transform="translate(172 44)">
    <circle r="24" fill="#FFF4B8" opacity="0.7"/>
    ${rays}
    <circle r="15" fill="${SUN}"/><circle r="11" fill="${SUN_CORE}"/>
  </g>
  <path d="M0 150 C60 130 130 134 220 146 L220 220 L0 220 Z" fill="${HILL_FAR}"/>
  <g>
    <path d="M108 104 C104 88 108 76 120 70" fill="none" stroke="${PIP_LINE}" stroke-width="5" stroke-linecap="round"/>
    <circle cx="122" cy="68" r="15" fill="${LIME}" opacity="0.35"/>
    <circle cx="122" cy="68" r="10" fill="url(#orb)" stroke="${INK}" stroke-width="3"/>
    <circle cx="119" cy="65" r="2.6" fill="#FFFFFF"/>
    <circle cx="110" cy="196" r="88" fill="url(#body)" stroke="${PIP_LINE}" stroke-width="4"/>
    <ellipse cx="72" cy="140" rx="22" ry="9" transform="rotate(-25 72 140)" fill="#FFFFFF" opacity="0.6"/>
    <ellipse cx="84" cy="168" rx="18" ry="21" fill="#FFFFFF" stroke="${PIP_LINE}" stroke-width="2.5"/>
    <ellipse cx="136" cy="168" rx="18" ry="21" fill="#FFFFFF" stroke="${PIP_LINE}" stroke-width="2.5"/>
    <ellipse cx="88" cy="172" rx="12" ry="14" fill="${INK}"/>
    <ellipse cx="140" cy="172" rx="12" ry="14" fill="${INK}"/>
    <circle cx="92" cy="165" r="4.5" fill="#FFFFFF"/>
    <circle cx="144" cy="165" r="4.5" fill="#FFFFFF"/>
    <ellipse cx="56" cy="188" rx="11" ry="7" fill="${BLUSH}" opacity="0.8"/>
    <ellipse cx="164" cy="188" rx="11" ry="7" fill="${BLUSH}" opacity="0.8"/>
  </g>
  <path d="M0 204 C70 192 150 194 220 200 L220 220 L0 220 Z" fill="${MEADOW}"/>
  <path d="M0 214 C80 206 150 208 220 212 L220 220 L0 220 Z" fill="${MEADOW_SHADE}"/>
</svg>`;

(async () => {
  const out = process.argv[2] || 'AppIcon.png';
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  await p.setContent(`<!doctype html><html><body style="margin:0">${svg(1024)}</body></html>`);
  await p.screenshot({ path: out, omitBackground: false });
  await b.close();
  console.log('wrote ' + out + ' (Pip peek, 1024)');
})();
