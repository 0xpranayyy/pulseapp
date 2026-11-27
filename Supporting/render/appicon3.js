// Round two. The first set failed for one reason: a 14px stroke floating in
// the middle of the tile. Every reference icon is a solid mass running to the
// edges, and most carry a formal idea beyond the obvious symbol. These are
// built to that brief — big shapes, few colours, something to notice.
const { chromium } = require('playwright');
const fs = require('fs');

function squircle(size, n = 5) {
  const r = size / 2, p = [], steps = 220;
  for (let i = 0; i <= steps; i++) {
    const t = (i/steps)*2*Math.PI, c = Math.cos(t), s = Math.sin(t);
    p.push(`${i?'L':'M'}${(r+Math.sign(c)*Math.pow(Math.abs(c),2/n)*r).toFixed(2)},${(r+Math.sign(s)*Math.pow(Math.abs(s),2/n)*r).toFixed(2)}`);
  }
  return p.join('') + 'Z';
}

// A wave surface across the tile at height y. This is the device that makes
// a probability read as alive rather than as a progress bar.
function wave(y, amp, phase = 0) {
  const pts = [];
  for (let x = -10; x <= 130; x += 2) {
    pts.push(`${x},${(y + Math.sin((x/34) + phase) * amp).toFixed(2)}`);
  }
  return 'M' + pts.join(' L');
}
const fillBelow = (y, amp, ph) => `${wave(y, amp, ph)} L130,130 L-10,130 Z`;

const INK = '#141A21';
const defs = `<defs>
  <linearGradient id="gi" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2E3845"/><stop offset="1" stop-color="#10151B"/></linearGradient>
  <linearGradient id="gs" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9EDCB0"/><stop offset="1" stop-color="#4FAE6C"/></linearGradient>
  <linearGradient id="gb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F9C5CE"/><stop offset="1" stop-color="#DC7183"/></linearGradient>
  <linearGradient id="gy" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F9EAAB"/><stop offset="1" stop-color="#DFBC4C"/></linearGradient>
  <linearGradient id="gl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D4C8F2"/><stop offset="1" stop-color="#A08EDC"/></linearGradient>
  <linearGradient id="gc" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#EDE6D8"/></linearGradient>
  <linearGradient id="gk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7FD79B"/><stop offset="1" stop-color="#36A05C"/></linearGradient>
</defs>`;

const items = [
  { id:'P1', name:'Level', idea:'A market at 64%, with a living surface.',
    art:`<rect width="120" height="120" fill="url(#gi)"/>
         <circle cx="60" cy="60" r="47" fill="#1C242E"/>
         <clipPath id="c1"><circle cx="60" cy="60" r="47"/></clipPath>
         <g clip-path="url(#c1)"><path d="${fillBelow(52,5)}" fill="url(#gk)"/></g>` },

  { id:'P2', name:'Oracle', idea:'The same level, with someone behind it.',
    art:`<rect width="120" height="120" fill="url(#gy)"/>
         <circle cx="60" cy="60" r="49" fill="#F6F2E8"/>
         <clipPath id="c2"><circle cx="60" cy="60" r="49"/></clipPath>
         <g clip-path="url(#c2)"><path d="${fillBelow(66,5)}" fill="url(#gk)"/></g>
         <ellipse cx="45" cy="47" rx="8.5" ry="11.5" fill="${INK}"/>
         <ellipse cx="76" cy="47" rx="8.5" ry="11.5" fill="${INK}"/>` },

  { id:'P3', name:'Two minds', idea:'Yes and No overlapping; the overlap is the price.',
    art:`<rect width="120" height="120" fill="url(#gc)"/>
         <g style="mix-blend-mode:multiply">
           <circle cx="44" cy="60" r="38" fill="#6FC78C"/>
           <circle cx="76" cy="60" r="38" fill="#EE93A2"/>
         </g>` },

  { id:'P4', name:'Flip', idea:'Two chevrons, up and down, locked into a disc.',
    art:`<rect width="120" height="120" fill="url(#gi)"/>
         <path d="M14,74 L40,38 L60,66 L60,112 L14,112 Z" fill="#5FBE7E"/>
         <path d="M106,46 L80,82 L60,54 L60,8 L106,8 Z" fill="#E98A9A"/>` },

  { id:'P5', name:'Massif', idea:'The pulse as solid ground, not a line.',
    art:`<rect width="120" height="120" fill="url(#gl)"/>
         <path d="M-6,98 L22,98 L40,56 L56,104 L74,24 L92,70 L126,70 L126,130 L-6,130 Z"
               fill="${INK}"/>` },

  { id:'P6', name:'Beacon', idea:'A gauge that stops where the market stands.',
    art:`<rect width="120" height="120" fill="url(#gi)"/>
         <circle cx="60" cy="60" r="40" fill="none" stroke="#263040" stroke-width="22"/>
         <circle cx="60" cy="60" r="40" fill="none" stroke="url(#gk)" stroke-width="22"
                 stroke-linecap="round" stroke-dasharray="161 251"
                 transform="rotate(-90 60 60)"/>
         <circle cx="60" cy="60" r="13" fill="#9EDCB0"/>` },

  { id:'P7', name:'Split', idea:'One tile, two futures, nothing else.',
    art:`<rect width="120" height="120" fill="url(#gc)"/>
         <path d="M0,0 H120 V120 H0 Z" fill="url(#gk)"/>
         <path d="M120,0 V120 H0 Z" fill="#E4798B"/>
         <circle cx="60" cy="60" r="19" fill="#F6F2E8"/>` },

  { id:'P8', name:'Pip', idea:'A creature made of the spike itself.',
    art:`<rect width="120" height="120" fill="url(#gb)"/>
         <path d="M60,6 C88,6 108,26 108,56 C108,92 86,114 60,114
                  C34,114 12,92 12,56 C12,26 32,6 60,6 Z" fill="${INK}"/>
         <circle cx="44" cy="52" r="9" fill="#fff"/>
         <circle cx="78" cy="52" r="9" fill="#fff"/>
         <path d="M34,84 L50,84 L60,70 L72,96 L86,80" fill="none" stroke="#F9C5CE"
               stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>` },
];

const tile = (c, px) => `<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
${defs}<clipPath id="q${c.id}${px}"><path d="${squircle(120)}"/></clipPath>
<g clip-path="url(#q${c.id}${px})">${c.art}</g></svg>`;

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
 body{margin:0;background:#09090A;font-family:ui-sans-serif,system-ui,sans-serif;padding:46px}
 h1{color:#fff;text-align:center;font-size:16px;letter-spacing:.15em;font-weight:600;margin:0 0 5px}
 .s{color:#70757D;text-align:center;font-size:12px;margin-bottom:40px}
 .g{display:grid;grid-template-columns:repeat(4,1fr);gap:38px 30px;max-width:1180px;margin:0 auto}
 .c{text-align:center}.t{display:flex;align-items:flex-end;justify-content:center;gap:13px;margin-bottom:12px}
 .nm{color:#fff;font-size:13.5px;font-weight:600}.id{color:#5D636C;font-size:11px;font-weight:700;letter-spacing:.06em}
 .i{color:#868C95;font-size:11.5px;line-height:1.45;margin-top:5px;padding:0 6px}
</style></head><body>
<h1>PULSE — ICON, ROUND TWO</h1>
<div class="s">solid masses to the edge · 150px and 60px</div>
<div class="g">${items.map(c=>`<div class="c"><div class="t">
 <span style="filter:drop-shadow(0 10px 26px rgba(0,0,0,.62))">${tile(c,150)}</span>${tile(c,60)}</div>
 <div class="id">${c.id}</div><div class="nm">${c.name}</div><div class="i">${c.idea}</div></div>`).join('')}</div>
</body></html>`;

fs.writeFileSync('icons3.html', html);
(async()=>{const b=await chromium.launch();
 const p=await b.newPage({viewport:{width:1280,height:980},deviceScaleFactor:2});
 await p.goto('file://'+process.cwd()+'/icons3.html');await p.waitForTimeout(400);
 await p.screenshot({path:'app-icons-3.png',fullPage:true});await b.close();console.log('ok');})();
