// Third register: drawn, not constructed. The reference set (Bunpo, daplit,
// Nurio, One Year, grug) shares confident line work, white ground, and a
// joke or an observation rather than a symbol. Geometry is the wrong tool
// here, so these are line drawings with deliberate asymmetry — a perfect
// circle reads as clip art in this company.
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

const K = '#15161A';            // ink
const PAPER = '#FFFFFF';
const CREAM = '#FBF8F1';
const LIME = '#D9F930';
const VIOLET = '#8E5BD0';
const GREEN = '#3DA86A';

// Grid paper, as Nurio uses — stops a white tile reading as unfinished.
const grid = (c = '#DCE6F2') => {
  let g = '';
  for (let i = 12; i < 120; i += 12)
    g += `<path d="M${i},0 V120" stroke="${c}" stroke-width="0.8"/><path d="M0,${i} H120" stroke="${c}" stroke-width="0.8"/>`;
  return g;
};

const pen = (d, w = 5.5, c = K) =>
  `<path d="${d}" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;

// A line with the wobble of something drawn rather than plotted.
const MARKET = 'M12,84 C26,83 30,86 40,72 C47,62 50,74 58,58 C64,46 70,66 78,44 C84,28 92,36 108,30';

const items = [
  { id:'D1', name:'Peek', idea:'Something watching the line, hands on the edge.',
    bg:PAPER, art:`
      ${pen(MARKET, 5, K)}
      <path d="M36,104 C36,88 48,80 60,80 C72,80 84,88 84,104 Z" fill="${K}"/>
      <circle cx="51" cy="93" r="4.6" fill="#fff"/><circle cx="69" cy="93" r="4.6" fill="#fff"/>
      <circle cx="52.4" cy="94" r="2" fill="${K}"/><circle cx="70.4" cy="94" r="2" fill="${K}"/>
      ${pen('M40,80 C40,74 44,72 46,76', 4, K)}
      ${pen('M80,80 C80,74 76,72 74,76', 4, K)}` },

  { id:'D2', name:'pulse.', idea:'Hand-lettered. The grug move — no symbol at all.',
    bg:PAPER, art:`
      <text x="60" y="70" text-anchor="middle" fill="${K}"
        style="font:700 33px ui-rounded,Allo,system-ui" letter-spacing="-1.2">pulse</text>
      <circle cx="94" cy="68" r="4.4" fill="${LIME}" stroke="${K}" stroke-width="2.4"/>
      ${pen('M30,82 C44,81 52,83 62,79 C72,75 80,84 92,78', 3.2, '#B9BDC6')}` },

  { id:'D3', name:'Tightrope', idea:'A bet is balance. The line wobbles under it.',
    bg:CREAM, art:`
      ${pen('M8,74 C28,70 40,80 60,74 C80,68 94,78 112,72', 4.4, K)}
      <ellipse cx="60" cy="56" rx="15" ry="17" fill="${VIOLET}"/>
      <circle cx="54.5" cy="53" r="3.6" fill="#fff"/><circle cx="66" cy="53" r="3.6" fill="#fff"/>
      <circle cx="55.4" cy="54" r="1.7" fill="${K}"/><circle cx="66.9" cy="54" r="1.7" fill="${K}"/>
      ${pen('M46,52 C40,44 34,44 30,50', 3.6, K)}
      ${pen('M74,52 C80,44 86,44 90,50', 3.6, K)}
      ${pen('M56,73 L56,66 M64,73 L64,66', 3.4, K)}` },

  { id:'D4', name:'Fingers crossed', idea:'What everyone does before it resolves.',
    bg:PAPER, art:`
      ${pen('M44,106 C42,86 44,70 46,56 C47,48 56,47 56,56 L56,76', 6, K)}
      ${pen('M58,56 C60,46 69,47 68,57 C67,67 60,70 58,78', 6, K)}
      ${pen('M70,62 C72,54 80,56 79,64 L77,80', 6, K)}
      ${pen('M40,104 C52,110 70,110 80,102 C86,96 86,86 84,78', 6, K)}
      <circle cx="96" cy="34" r="7" fill="${LIME}" stroke="${K}" stroke-width="2.6"/>` },

  { id:'D5', name:'Two cats', idea:'Yes and No, one of them about to be wrong.',
    bg:CREAM, art:`
      <path d="M26,100 L26,70 L34,78 L44,74 L54,78 L62,70 L62,100 Z" fill="${K}"/>
      <circle cx="38" cy="86" r="3.4" fill="${LIME}"/><circle cx="52" cy="86" r="3.4" fill="${LIME}"/>
      <path d="M64,100 L64,76 L72,82 L80,78 L88,82 L96,76 L96,100 Z" fill="#C8CCD4"/>
      <circle cx="74" cy="88" r="3" fill="#fff"/><circle cx="86" cy="88" r="3" fill="#fff"/>
      ${pen('M14,52 C34,50 44,34 60,40 C76,46 88,30 108,32', 4.4, K)}` },

  { id:'D6', name:'The watcher', idea:'One eye, drawn. Bunpo-plain.',
    bg:PAPER, art:`
      ${pen('M18,62 C34,34 86,34 102,62 C86,90 34,90 18,62 Z', 5.4, K)}
      <circle cx="60" cy="62" r="15" fill="${K}"/>
      <circle cx="55" cy="57" r="4.6" fill="#fff"/>
      ${pen('M34,96 C48,92 58,98 70,94 C80,91 86,98 96,95', 3.4, '#B9BDC6')}` },

  { id:'D7', name:'Banana run', idea:'Nurio energy: a creature carrying the number.',
    bg:'#FEFCF4', art:`${grid('#E2EAF4')}
      <ellipse cx="56" cy="72" rx="17" ry="20" fill="#8FC3F0"/>
      <circle cx="50" cy="68" r="3.4" fill="${K}"/><circle cx="62" cy="68" r="3.4" fill="${K}"/>
      ${pen('M51,78 C55,82 59,82 62,78', 2.8, K)}
      ${pen('M42,60 C38,48 42,40 48,38', 5, '#8FC3F0')}
      ${pen('M70,60 C74,48 70,40 64,38', 5, '#8FC3F0')}
      ${pen('M40,36 C52,26 72,26 84,34', 7.5, LIME)}
      ${pen('M44,96 L40,106 M68,96 L72,106', 5, '#8FC3F0')}` },

  { id:'D8', name:'Sprout', idea:'One Year: a single clean line, nothing else.',
    bg:PAPER, art:`
      ${pen('M60,104 L60,52', 5, VIOLET)}
      ${pen('M60,70 C44,70 38,60 40,50 C52,48 60,58 60,70', 5, VIOLET)}
      ${pen('M60,60 C76,60 82,50 80,40 C68,38 60,48 60,60', 5, VIOLET)}
      ${pen('M24,88 C38,86 44,90 56,84', 4, GREEN)}
      <circle cx="60" cy="34" r="8" fill="${LIME}" stroke="${VIOLET}" stroke-width="4"/>` },
];

const tile = (c, px) => `<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
<clipPath id="z${c.id}${px}"><path d="${squircle(120)}"/></clipPath>
<g clip-path="url(#z${c.id}${px})"><rect width="120" height="120" fill="${c.bg}"/>${c.art}</g></svg>`;

const html = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="shared.css"><style>
 body{display:block;margin:0;background:#0B0B0D;font-family:Allo,ui-sans-serif,system-ui,sans-serif;padding:46px}
 h1{color:#fff;text-align:center;font-size:16px;letter-spacing:.15em;font-weight:700;margin:0 0 5px}
 .s{color:#70757D;text-align:center;font-size:12px;margin-bottom:38px}
 .g{display:grid;grid-template-columns:repeat(4,1fr);gap:36px 28px;max-width:1180px;margin:0 auto}
 .c{text-align:center}.t{display:flex;align-items:flex-end;justify-content:center;gap:13px;margin-bottom:12px}
 .nm{color:#fff;font-size:13.5px;font-weight:700}
 .i{color:#868C95;font-size:11.5px;line-height:1.45;margin-top:5px;padding:0 6px}
</style></head><body>
<h1>PULSE — DRAWN</h1><div class="s">150px and 60px · white grounds, line work, one idea each</div>
<div class="g">${items.map(c=>`<div class="c"><div class="t">
 <span style="filter:drop-shadow(0 10px 26px rgba(0,0,0,.55))">${tile(c,150)}</span>${tile(c,60)}</div>
 <div class="nm">${c.name}</div><div class="i">${c.idea}</div></div>`).join('')}</div></body></html>`;

fs.writeFileSync('icons5.html', html);
(async()=>{const b=await chromium.launch();
 const p=await b.newPage({viewport:{width:1280,height:980},deviceScaleFactor:2});
 await p.goto('file://'+process.cwd()+'/icons5.html');
 await p.evaluate(()=>document.fonts.ready); await p.waitForTimeout(500);
 await p.screenshot({path:'app-icons-5.png',fullPage:true});await b.close();console.log('ok');})();
