// Oracle, refined. The idea holds: the filled level is the market price and
// the face sits in it, so the icon says "a market, alive" rather than
// "a heartbeat". What round two got wrong was amplitude — the wave was so
// shallow it read as a flat fill, which is a progress bar, not a pulse.
const { chromium } = require('playwright');
const fs = require('fs');

function squircle(size, n = 5) {
  const r = size/2, p = [], steps = 240;
  for (let i = 0; i <= steps; i++) {
    const t = (i/steps)*2*Math.PI, c = Math.cos(t), s = Math.sin(t);
    p.push(`${i?'L':'M'}${(r+Math.sign(c)*Math.pow(Math.abs(c),2/n)*r).toFixed(2)},${(r+Math.sign(s)*Math.pow(Math.abs(s),2/n)*r).toFixed(2)}`);
  }
  return p.join('')+'Z';
}
function waveFill(y, amp, ph = 0) {
  const pts = [];
  for (let x = -14; x <= 134; x += 1.5) pts.push(`${x},${(y + Math.sin(x/26 + ph)*amp).toFixed(2)}`);
  return 'M' + pts.join(' L') + ' L134,134 L-14,134 Z';
}

const INK = '#141A21';
const defs = `<defs>
 <linearGradient id="y" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F9E9A6"/><stop offset="1" stop-color="#DEB942"/></linearGradient>
 <linearGradient id="k" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2F3A47"/><stop offset="1" stop-color="#10151B"/></linearGradient>
 <linearGradient id="l" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D3C6F2"/><stop offset="1" stop-color="#9D8ADA"/></linearGradient>
 <linearGradient id="p" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F9C4CD"/><stop offset="1" stop-color="#DD7083"/></linearGradient>
 <linearGradient id="grn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#86D9A2"/><stop offset="1" stop-color="#36A35E"/></linearGradient>
 <linearGradient id="cream" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFDF8"/><stop offset="1" stop-color="#F0E9DA"/></linearGradient>
</defs>`;

// bg, body, level colour, level height, amplitude, eye y, eye colour
function oracle({bg, body, lvl, y, amp, ey, eye = INK, r = 49, erx = 9, ery = 12}) {
  return `<rect width="120" height="120" fill="${bg}"/>
  <circle cx="60" cy="60" r="${r}" fill="${body}"/>
  <clipPath id="o${y}${amp}${ey}"><circle cx="60" cy="60" r="${r}"/></clipPath>
  <g clip-path="url(#o${y}${amp}${ey})"><path d="${waveFill(y, amp)}" fill="${lvl}"/></g>
  <ellipse cx="44" cy="${ey}" rx="${erx}" ry="${ery}" fill="${eye}"/>
  <ellipse cx="76" cy="${ey}" rx="${erx}" ry="${ery}" fill="${eye}"/>
  <ellipse cx="47" cy="${ey-4}" rx="3.1" ry="3.8" fill="#fff" opacity=".95"/>
  <ellipse cx="79" cy="${ey-4}" rx="3.1" ry="3.8" fill="#fff" opacity=".95"/>`;
}

const items = [
  { id:'O1', name:'Oracle · steady', idea:'Level low, face clear. The calm read.',
    art: oracle({bg:'url(#y)', body:'#FBF7EC', lvl:'url(#grn)', y:76, amp:6, ey:50}) },

  { id:'O2', name:'Oracle · rising', idea:'Market up to the eyes. Tension.',
    art: oracle({bg:'url(#y)', body:'#FBF7EC', lvl:'url(#grn)', y:62, amp:7, ey:44}) },

  { id:'O3', name:'Oracle · submerged', idea:'Eyes just above the line — peering over.',
    art: oracle({bg:'url(#y)', body:'#FBF7EC', lvl:'url(#grn)', y:54, amp:6.5, ey:38}) },

  { id:'O4', name:'Oracle · ink', idea:'Same creature, night shift.',
    art: oracle({bg:'url(#k)', body:'#1E2733', lvl:'url(#grn)', y:70, amp:6.5, ey:48, eye:'#F3F0E6'}) },

  { id:'O5', name:'Oracle · lilac', idea:'Cooler ground, green still the market.',
    art: oracle({bg:'url(#l)', body:'#FBF7EC', lvl:'url(#grn)', y:72, amp:6.5, ey:48}) },

  { id:'O6', name:'Oracle · wide', idea:'Body to the edge, eyes bigger and closer.',
    art: oracle({bg:'url(#p)', body:'#FBF7EC', lvl:'url(#grn)', y:74, amp:7, ey:48, r:55, erx:10.5, ery:14}) },

  { id:'A1', name:'Two minds', idea:'Alternate: Yes and No overlapping.',
    art:`<rect width="120" height="120" fill="url(#cream)"/>
         <g style="mix-blend-mode:multiply">
           <circle cx="43" cy="60" r="40" fill="#5FC281"/>
           <circle cx="77" cy="60" r="40" fill="#ED8898"/></g>` },

  { id:'A2', name:'Massif', idea:'Alternate: the pulse as solid ground.',
    art:`<rect width="120" height="120" fill="url(#l)"/>
         <path d="M-6,100 L20,100 L38,58 L55,106 L74,22 L93,72 L126,72 L126,132 L-6,132 Z" fill="${INK}"/>` },
];

const tile = (c, px) => `<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
${defs}<clipPath id="s${c.id}${px}"><path d="${squircle(120)}"/></clipPath>
<g clip-path="url(#s${c.id}${px})">${c.art}</g></svg>`;

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
 body{margin:0;background:#09090A;font-family:ui-sans-serif,system-ui,sans-serif;padding:46px}
 h1{color:#fff;text-align:center;font-size:16px;letter-spacing:.15em;font-weight:600;margin:0 0 5px}
 .s{color:#70757D;text-align:center;font-size:12px;margin-bottom:38px}
 .g{display:grid;grid-template-columns:repeat(4,1fr);gap:36px 28px;max-width:1180px;margin:0 auto 46px}
 .c{text-align:center}.t{display:flex;align-items:flex-end;justify-content:center;gap:13px;margin-bottom:11px}
 .nm{color:#fff;font-size:13px;font-weight:600}.i{color:#868C95;font-size:11.5px;line-height:1.45;margin-top:4px;padding:0 6px}
 .hs{max-width:400px;margin:0 auto;background:linear-gradient(165deg,#455270,#222937);border-radius:32px;
     padding:26px 24px 30px;display:grid;grid-template-columns:repeat(4,1fr);gap:20px 14px}
 .lb{color:#fff;font-size:9.5px;text-align:center;margin-top:5px}
 .ph{width:60px;height:60px;border-radius:14px;background:rgba(255,255,255,.13);margin:0 auto}
 h2{color:#6E737B;text-align:center;font-size:11px;letter-spacing:.14em;margin:0 0 16px;font-weight:600}
</style></head><body>
<h1>ORACLE — REFINED</h1><div class="s">150px and 60px</div>
<div class="g">${items.map(c=>`<div class="c"><div class="t">
 <span style="filter:drop-shadow(0 10px 26px rgba(0,0,0,.62))">${tile(c,150)}</span>${tile(c,60)}</div>
 <div class="nm">${c.name}</div><div class="i">${c.idea}</div></div>`).join('')}</div>
<h2>ON A HOME SCREEN</h2>
<div class="hs">${['O1','O3','O4','A1'].map(id=>{const c=items.find(i=>i.id===id);
 return `<div>${tile(c,60)}<div class="lb">Pulse</div></div>`;}).join('')}
 ${Array.from({length:8}).map(()=>'<div><div class="ph"></div><div class="lb">&nbsp;</div></div>').join('')}</div>
</body></html>`;

fs.writeFileSync('icons4.html', html);
(async()=>{const b=await chromium.launch();
 const p=await b.newPage({viewport:{width:1280,height:1000},deviceScaleFactor:2});
 await p.goto('file://'+process.cwd()+'/icons4.html');await p.waitForTimeout(400);
 await p.screenshot({path:'app-icons-4.png',fullPage:true});await b.close();console.log('ok');})();
