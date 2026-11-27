// App-icon candidates for Pulse, rendered as real tiles and re-rendered at
// 60px so a mark that only works poster-size is caught here rather than on a
// home screen. Colours are the app's own pastels, not invented for the icon.
const { chromium } = require('playwright');
const fs = require('fs');

// iOS squircle. A plain rounded rect reads subtly wrong next to real icons;
// the superellipse is the shape the platform actually uses.
function squircle(size, n = 5) {
  const r = size / 2, pts = [], steps = 180;
  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * 2 * Math.PI;
    const c = Math.cos(t), s = Math.sin(t);
    const x = r + Math.sign(c) * Math.pow(Math.abs(c), 2 / n) * r;
    const y = r + Math.sign(s) * Math.pow(Math.abs(s), 2 / n) * r;
    pts.push(`${i ? 'L' : 'M'}${x.toFixed(2)},${y.toFixed(2)}`);
  }
  return pts.join('') + 'Z';
}

const C = {
  ink:'#12171D', inkUp:'#2A3340',
  sage:'#8FD3A3', sageDeep:'#1F5A2E',
  blush:'#F0A8B4', blushDeep:'#8C2437',
  butter:'#EFD98E', sky:'#A8CBE6', lilac:'#C3B5E8',
  mist:'#A6D2CD', clay:'#E0C29C', plum:'#D9B5D2',
  cream:'#F7F4EE', white:'#FFFFFF',
};

// The pulse figure: four segments, no more. Anything finer closes up at 60px.
const PULSE = 'M14,70 L40,70 L56,34 L74,86 L88,52 L106,52';

const defs = `
<defs>
  <linearGradient id="gInk" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="${C.inkUp}"/><stop offset="1" stop-color="${C.ink}"/></linearGradient>
  <linearGradient id="gSage" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#A8E0B8"/><stop offset="1" stop-color="#5FB87C"/></linearGradient>
  <linearGradient id="gBlush" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#F6BCC6"/><stop offset="1" stop-color="#E2808F"/></linearGradient>
  <linearGradient id="gButter" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#F7E7A6"/><stop offset="1" stop-color="#E3C45F"/></linearGradient>
  <linearGradient id="gLilac" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#D2C6F0"/><stop offset="1" stop-color="#A692DC"/></linearGradient>
  <linearGradient id="gCream" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#EFE9DE"/></linearGradient>
  <linearGradient id="gSky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#C2DCEF"/><stop offset="1" stop-color="#7FB0D4"/></linearGradient>
</defs>`;

const stroke = (d, c, w) =>
  `<path d="${d}" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;

const candidates = [
  { id:'A', name:'Pulse line',
    note:'The mark itself. One idea, maximum weight.',
    bg:'url(#gInk)', art: stroke(PULSE, C.sage, 15) },

  { id:'B', name:'Split pulse',
    note:'Yes and No as the two halves; the line crosses the seam.',
    bg:'url(#gInk)',
    art:`<path d="M0,0 H60 V120 H0Z" fill="${C.sageDeep}" opacity="0.95"/>
         <path d="M60,0 H120 V120 H60Z" fill="${C.blushDeep}" opacity="0.95"/>
         ${stroke(PULSE, C.cream, 15)}`},

  { id:'C', name:'Pulse face',
    note:'Two eyes, a pulse for a mouth. Duolingo register.',
    bg:'url(#gSage)',
    art:`<ellipse cx="44" cy="46" rx="11" ry="14" fill="${C.ink}"/>
         <ellipse cx="80" cy="46" rx="11" ry="14" fill="${C.ink}"/>
         <ellipse cx="47.5" cy="41" rx="3.6" ry="4.4" fill="#fff" opacity="0.9"/>
         <ellipse cx="83.5" cy="41" rx="3.6" ry="4.4" fill="#fff" opacity="0.9"/>
         ${stroke('M36,80 L52,80 L62,66 L74,92 L84,78 L92,78', C.ink, 9)}`},

  { id:'D', name:'Beat',
    note:'Pulse inside a ring: a reading, not a decoration.',
    bg:'url(#gInk)',
    art:`<circle cx="60" cy="60" r="40" fill="none" stroke="${C.sage}" stroke-width="9" opacity="0.28"/>
         ${stroke('M26,62 L46,62 L57,38 L71,84 L80,56 L94,56', C.sage, 12)}`},

  { id:'E', name:'Monogram P',
    note:'A P whose counter is the spike.',
    bg:'url(#gLilac)',
    art:`<path d="M38,96 V26 H68 a21,21 0 0 1 0,42 H38" fill="none" stroke="${C.ink}"
           stroke-width="15" stroke-linecap="round" stroke-linejoin="round"/>
         ${stroke('M52,47 L58,36 L64,58 L70,47', C.ink, 7)}`},

  { id:'F', name:'Two outcomes',
    note:'Eyes as Yes and No. Reads as a face, means a binary.',
    bg:'url(#gCream)',
    art:`<circle cx="43" cy="60" r="20" fill="${C.sageDeep}"/>
         <circle cx="77" cy="60" r="20" fill="${C.blushDeep}"/>
         ${stroke('M34,60 L40,60 L43,52 L47,68 L50,60 L52,60', '#fff', 5)}
         ${stroke('M68,60 L86,60', '#fff', 5)}`},

  { id:'G', name:'Rising',
    note:'Pulse that resolves upward and stops on a point.',
    bg:'url(#gButter)',
    art:`${stroke('M16,78 L38,78 L52,48 L66,88 L80,40', C.ink, 14)}
         <circle cx="80" cy="40" r="11" fill="${C.ink}"/>
         <circle cx="80" cy="40" r="4.5" fill="${C.butter}"/>`},

  { id:'H', name:'Chambers',
    note:'Two bars, one pulse. The book and the beat together.',
    bg:'url(#gSky)',
    art:`<rect x="26" y="52" width="17" height="42" rx="8.5" fill="${C.ink}" opacity="0.22"/>
         <rect x="77" y="38" width="17" height="56" rx="8.5" fill="${C.ink}" opacity="0.22"/>
         ${stroke('M22,66 L44,66 L58,34 L74,88 L86,58 L98,58', C.ink, 13)}`},
];

const tile = (c, px) => `
<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
  ${defs}
  <clipPath id="sq${c.id}${px}"><path d="${squircle(120)}"/></clipPath>
  <g clip-path="url(#sq${c.id}${px})">
    <rect width="120" height="120" fill="${c.bg}"/>
    ${c.art}
  </g>
</svg>`;

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
  body{margin:0;background:#0B0B0C;font-family:ui-sans-serif,system-ui,-apple-system,sans-serif;padding:48px}
  .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:40px 32px;max-width:1180px;margin:0 auto}
  .cell{text-align:center}
  .tiles{display:flex;align-items:flex-end;justify-content:center;gap:14px;margin-bottom:14px}
  .big{filter:drop-shadow(0 10px 26px rgba(0,0,0,.6))}
  .id{color:#fff;font-weight:700;font-size:15px;letter-spacing:.02em}
  .nm{color:#fff;font-weight:600;font-size:13px;margin-top:2px}
  .nt{color:#8A8F98;font-size:11.5px;line-height:1.45;margin-top:5px;padding:0 4px}
  h1{color:#fff;text-align:center;font-size:17px;font-weight:600;letter-spacing:.14em;margin:0 0 6px}
  .sub{color:#71767E;text-align:center;font-size:12px;margin-bottom:40px}
</style></head><body>
<h1>PULSE — APP ICON</h1>
<div class="sub">each candidate at 168px and at 60px, the size it ships at on a home screen</div>
<div class="grid">
${candidates.map(c => `<div class="cell">
  <div class="tiles"><span class="big">${tile(c,168)}</span>${tile(c,60)}</div>
  <div class="id">${c.id}</div><div class="nm">${c.name}</div><div class="nt">${c.note}</div>
</div>`).join('')}
</div></body></html>`;

fs.writeFileSync('icons.html', html);
candidates.forEach(c => fs.writeFileSync(`icon-${c.id}.svg`, tile(c, 1024).trim()));

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport:{width:1280,height:1000}, deviceScaleFactor:2 });
  await p.goto('file://' + process.cwd() + '/icons.html');
  await p.waitForTimeout(400);
  await p.screenshot({ path:'app-icons.png', fullPage:true });
  await b.close();
  console.log('rendered ' + candidates.length + ' candidates');
})();
