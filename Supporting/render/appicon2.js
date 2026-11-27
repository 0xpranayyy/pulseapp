// Second pass: the three that survived 60px, plus colourways for the leader.
const { chromium } = require('playwright');
const fs = require('fs');

function squircle(size, n = 5) {
  const r = size / 2, pts = [], steps = 220;
  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * 2 * Math.PI, c = Math.cos(t), s = Math.sin(t);
    pts.push(`${i?'L':'M'}${(r+Math.sign(c)*Math.pow(Math.abs(c),2/n)*r).toFixed(2)},${(r+Math.sign(s)*Math.pow(Math.abs(s),2/n)*r).toFixed(2)}`);
  }
  return pts.join('') + 'Z';
}
const INK = '#141A21';

// Tuned: the spike now peaks slightly left of centre and the run-up is longer,
// so the eye travels before it climbs. The terminal dot sits ON the apex.
const RISE = 'M18,80 L40,80 L54,46 L68,90 L82,38';
const DOT  = { x: 82, y: 38 };

const grad = (id, a, b) =>
  `<linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`;

const defs = `<defs>
${grad('butter','#F8E9AC','#E0BF54')}
${grad('sage','#A9E1B9','#55B274')}
${grad('blush','#F8C3CC','#DE7C8C')}
${grad('ink','#2C3542','#11161C')}
${grad('cream','#FFFFFF','#EDE6D9')}
${grad('sageDeep','#2E7A45','#17482A')}
${grad('blushDeep','#A62F45','#731B2C')}
</defs>`;

const rising = (bg, fg, dotFill) => `
  <rect width="120" height="120" fill="${bg}"/>
  <path d="${RISE}" fill="none" stroke="${fg}" stroke-width="14.5"
        stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="${DOT.x}" cy="${DOT.y}" r="11.5" fill="${fg}"/>
  <circle cx="${DOT.x}" cy="${DOT.y}" r="4.6" fill="${dotFill}"/>`;

const items = [
  { id:'G1', name:'Rising · butter', art: rising('url(#butter)', INK, '#EFD98E') },
  { id:'G2', name:'Rising · ink',    art: rising('url(#ink)', '#8FD3A3', '#141A21') },
  { id:'G3', name:'Rising · sage',   art: rising('url(#sage)', INK, '#8FD3A3') },
  { id:'G4', name:'Rising · cream',  art: rising('url(#cream)', INK, '#F7F4EE') },

  { id:'B2', name:'Split pulse',
    art:`<path d="M0,0 H60 V120 H0Z" fill="url(#sageDeep)"/>
         <path d="M60,0 H120 V120 H60Z" fill="url(#blushDeep)"/>
         <path d="M16,72 L40,72 L55,36 L72,88 L86,50 L104,50" fill="none" stroke="#F7F4EE"
               stroke-width="14.5" stroke-linecap="round" stroke-linejoin="round"/>`},

  { id:'C2', name:'Pulse face',
    art:`<rect width="120" height="120" fill="url(#sage)"/>
         <ellipse cx="43" cy="48" rx="11.5" ry="15" fill="${INK}"/>
         <ellipse cx="81" cy="48" rx="11.5" ry="15" fill="${INK}"/>
         <ellipse cx="46.8" cy="42.5" rx="3.8" ry="4.6" fill="#fff" opacity="0.92"/>
         <ellipse cx="84.8" cy="42.5" rx="3.8" ry="4.6" fill="#fff" opacity="0.92"/>
         <path d="M38,82 L56,82 L66,70 L78,94" fill="none" stroke="${INK}"
               stroke-width="10.5" stroke-linecap="round" stroke-linejoin="round"/>`},
];

const tile = (c, px) => `<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
${defs}<clipPath id="k${c.id}${px}"><path d="${squircle(120)}"/></clipPath>
<g clip-path="url(#k${c.id}${px})">${c.art}</g></svg>`;

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
 body{margin:0;background:#09090A;font-family:ui-sans-serif,system-ui,sans-serif;padding:44px}
 h1{color:#fff;text-align:center;font-size:16px;letter-spacing:.14em;font-weight:600;margin:0 0 34px}
 .row{display:flex;justify-content:center;gap:30px;flex-wrap:wrap;max-width:1200px;margin:0 auto 44px}
 .c{text-align:center}
 .t{display:flex;align-items:flex-end;gap:12px;justify-content:center}
 .nm{color:#fff;font-size:12.5px;font-weight:600;margin-top:11px}
 .hs{max-width:430px;margin:0 auto;background:linear-gradient(170deg,#43506B,#232A3A);
     border-radius:34px;padding:30px 26px 34px;display:grid;grid-template-columns:repeat(4,1fr);gap:22px 16px}
 .hs .ic{text-align:center}
 .hs .lb{color:#fff;font-size:10px;margin-top:6px;opacity:.95}
 .ph{width:60px;height:60px;border-radius:14px;background:rgba(255,255,255,.14);margin:0 auto}
 h2{color:#777;text-align:center;font-size:11.5px;letter-spacing:.12em;margin:0 0 16px;font-weight:600}
</style></head><body>
<h1>SHORTLIST</h1>
<div class="row">${items.map(c=>`<div class="c"><div class="t">
  <span style="filter:drop-shadow(0 10px 24px rgba(0,0,0,.65))">${tile(c,150)}</span>${tile(c,60)}</div>
  <div class="nm">${c.name}</div></div>`).join('')}</div>
<h2>ON A HOME SCREEN</h2>
<div class="hs">
  ${['G1','G2','B2','C2'].map(id=>{const c=items.find(i=>i.id===id);
    return `<div class="ic">${tile(c,60)}<div class="lb">Pulse</div></div>`;}).join('')}
  ${Array.from({length:8}).map(()=>'<div class="ic"><div class="ph"></div><div class="lb">&nbsp;</div></div>').join('')}
</div></body></html>`;

fs.writeFileSync('icons2.html', html);
items.forEach(c => fs.writeFileSync(`final-${c.id}.svg`, tile(c, 1024).trim()));
(async()=>{const b=await chromium.launch();
 const p=await b.newPage({viewport:{width:1280,height:900},deviceScaleFactor:2});
 await p.goto('file://'+process.cwd()+'/icons2.html'); await p.waitForTimeout(400);
 await p.screenshot({path:'app-icons-2.png',fullPage:true}); await b.close();
 console.log('ok');})();
