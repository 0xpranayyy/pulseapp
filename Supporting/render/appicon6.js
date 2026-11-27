// Peek, refined. What makes the reference cats work is contact: paws over
// the edge. Without them the creature floats behind the line instead of
// holding on to it, which was the flaw in the first pass.
const { chromium } = require('playwright');
const fs = require('fs');

function squircle(size, n = 5) {
  const r = size/2, p = [], steps = 240;
  for (let i = 0; i <= steps; i++) {
    const t=(i/steps)*2*Math.PI, c=Math.cos(t), s=Math.sin(t);
    p.push(`${i?'L':'M'}${(r+Math.sign(c)*Math.pow(Math.abs(c),2/n)*r).toFixed(2)},${(r+Math.sign(s)*Math.pow(Math.abs(s),2/n)*r).toFixed(2)}`);
  }
  return p.join('')+'Z';
}
const K='#15161A', LIME='#D9F930', VIOLET='#8E5BD0';
const pen=(d,w,c)=>`<path d="${d}" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;

// The market line. It passes behind the head and in front of the paws, which
// is what sells "holding on" rather than "placed near".
const LINE='M10,78 C24,77 29,80 39,67 C46,57 49,69 57,53 C63,41 69,60 77,39 C83,24 93,31 110,26';

function peek({bg, line, body, ears=false, eyeRing=false}) {
  return `
  <rect width="120" height="120" fill="${bg}"/>
  ${pen(LINE, 5, line)}
  ${ears ? `<path d="M40,92 L41,78 L50,86 Z M80,92 L79,78 L70,86 Z" fill="${body}"/>` : ''}
  <path d="M36,112 C36,94 47,85 60,85 C73,85 84,94 84,112 Z" fill="${body}"/>
  <circle cx="51" cy="98" r="5" fill="#fff"/><circle cx="69" cy="98" r="5" fill="#fff"/>
  <circle cx="52.6" cy="99.2" r="2.2" fill="${K}"/><circle cx="70.6" cy="99.2" r="2.2" fill="${K}"/>
  ${eyeRing ? `<circle cx="51" cy="98" r="5" fill="none" stroke="${K}" stroke-width="1.2"/>
               <circle cx="69" cy="98" r="5" fill="none" stroke="${K}" stroke-width="1.2"/>` : ''}
  <!-- paws, hooked over the line -->
  <path d="M34,86 C34,81 38,79 42,81 C45,82.5 45,87 42,88 L36,89 Z" fill="${body}"/>
  <path d="M86,86 C86,81 82,79 78,81 C75,82.5 75,87 78,88 L84,89 Z" fill="${body}"/>`;
}

const items=[
  { id:'K1', name:'Peek · ink on white', idea:'The plainest. Reads at any size.',
    art: peek({bg:'#FFFFFF', line:K, body:K}) },
  { id:'K2', name:'Peek · lime line', idea:'The market is the accent; the creature is ink.',
    art: peek({bg:'#FFFFFF', line:LIME, body:K}) },
  { id:'K3', name:'Peek · ears', idea:'Ears make it a someone rather than a shape.',
    art: peek({bg:'#FFFBF2', line:K, body:K, ears:true}) },
  { id:'K4', name:'Peek · violet', idea:'Creature in the brand violet, lime line.',
    art: peek({bg:'#FFFFFF', line:LIME, body:VIOLET, ears:true}) },
  { id:'K5', name:'Peek · night', idea:'Dark tile, so it sits with the app not against it.',
    art: peek({bg:'#15121C', line:LIME, body:'#FFFFFF', ears:true, eyeRing:true}) },
  { id:'K6', name:'Peek · violet ground', idea:'Brand ground, cream creature.',
    art: peek({bg:'#8E5BD0', line:LIME, body:'#FFFBF2', ears:true, eyeRing:true}) },

  { id:'K7', name:'Two cats', idea:'Alternate: Yes and No, one about to be wrong.',
    art:`<rect width="120" height="120" fill="#FFFBF2"/>
      ${pen('M14,52 C34,50 44,34 60,40 C76,46 88,30 108,32', 4.6, K)}
      <path d="M24,102 L24,70 L33,79 L44,74 L55,79 L64,70 L64,102 Z" fill="${K}"/>
      <circle cx="38" cy="87" r="3.6" fill="${LIME}"/><circle cx="52" cy="87" r="3.6" fill="${LIME}"/>
      <path d="M62,102 L62,77 L70,84 L79,79 L88,84 L96,77 L96,102 Z" fill="#C6CAD3"/>
      <circle cx="73" cy="89" r="3.1" fill="#fff"/><circle cx="86" cy="89" r="3.1" fill="#fff"/>` },

  { id:'K8', name:'The watcher', idea:'Alternate: one eye, Bunpo-plain.',
    art:`<rect width="120" height="120" fill="#FFFFFF"/>
      ${pen('M18,62 C34,34 86,34 102,62 C86,90 34,90 18,62 Z', 5.4, K)}
      <circle cx="60" cy="62" r="15" fill="${K}"/><circle cx="55" cy="57" r="4.6" fill="#fff"/>
      ${pen('M34,96 C48,92 58,98 70,94 C80,91 86,98 96,95', 3.4, LIME)}` },
];

const tile=(c,px)=>`<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
<clipPath id="w${c.id}${px}"><path d="${squircle(120)}"/></clipPath>
<g clip-path="url(#w${c.id}${px})">${c.art}</g></svg>`;

const html=`<!doctype html><html><head><meta charset="utf-8"><style>
 body{margin:0;background:#0B0B0D;font-family:ui-sans-serif,system-ui,sans-serif;padding:46px}
 h1{color:#fff;text-align:center;font-size:16px;letter-spacing:.15em;font-weight:700;margin:0 0 5px}
 .s{color:#70757D;text-align:center;font-size:12px;margin-bottom:38px}
 .g{display:grid;grid-template-columns:repeat(4,1fr);gap:36px 28px;max-width:1180px;margin:0 auto 44px}
 .c{text-align:center}.t{display:flex;align-items:flex-end;justify-content:center;gap:13px;margin-bottom:11px}
 .nm{color:#fff;font-size:13px;font-weight:700}.i{color:#868C95;font-size:11.5px;line-height:1.45;margin-top:4px;padding:0 6px}
 .hs{max-width:400px;margin:0 auto;background:linear-gradient(165deg,#455270,#222937);border-radius:32px;
     padding:26px 24px 30px;display:grid;grid-template-columns:repeat(4,1fr);gap:20px 14px}
 .lb{color:#fff;font-size:9.5px;text-align:center;margin-top:5px}
 .ph{width:60px;height:60px;border-radius:14px;background:rgba(255,255,255,.13);margin:0 auto}
 h2{color:#6E737B;text-align:center;font-size:11px;letter-spacing:.14em;margin:0 0 16px;font-weight:700}
</style></head><body>
<h1>PEEK — REFINED</h1><div class="s">paws over the line · 150px and 60px</div>
<div class="g">${items.map(c=>`<div class="c"><div class="t">
 <span style="filter:drop-shadow(0 10px 26px rgba(0,0,0,.55))">${tile(c,150)}</span>${tile(c,60)}</div>
 <div class="nm">${c.name}</div><div class="i">${c.idea}</div></div>`).join('')}</div>
<h2>ON A HOME SCREEN</h2>
<div class="hs">${['K2','K4','K5','K7'].map(id=>{const c=items.find(i=>i.id===id);
 return `<div>${tile(c,60)}<div class="lb">Pulse</div></div>`;}).join('')}
 ${Array.from({length:8}).map(()=>'<div><div class="ph"></div><div class="lb">&nbsp;</div></div>').join('')}</div>
</body></html>`;

fs.writeFileSync('icons6.html',html);
(async()=>{const b=await chromium.launch();
 const p=await b.newPage({viewport:{width:1280,height:1000},deviceScaleFactor:2});
 await p.goto('file://'+process.cwd()+'/icons6.html');await p.waitForTimeout(400);
 await p.screenshot({path:'app-icons-6.png',fullPage:true});await b.close();console.log('ok');})();
