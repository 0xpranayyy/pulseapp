// Fewer options, much more care per curve. The previous pass shipped a
// featureless dome: no species, no pose, no craft. daplit's cat has ears,
// whiskers and a real silhouette; Nurio's bunny has limbs and a pose. A
// shape with two dots on it is not a character.
const { chromium } = require('playwright');
const fs = require('fs');

function squircle(size, n = 5) {
  const r=size/2,p=[],steps=240;
  for(let i=0;i<=steps;i++){const t=(i/steps)*2*Math.PI,c=Math.cos(t),s=Math.sin(t);
  p.push(`${i?'L':'M'}${(r+Math.sign(c)*Math.pow(Math.abs(c),2/n)*r).toFixed(2)},${(r+Math.sign(s)*Math.pow(Math.abs(s),2/n)*r).toFixed(2)}`);}
  return p.join('')+'Z';
}
const K='#15161A', LIME='#D9F930', VIOLET='#8E5BD0', CREAM='#FFFBF2';
const pen=(d,w,c,o=1)=>`<path d="${d}" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" opacity="${o}"/>`;

const LINE='M8,66 C22,64 27,68 37,55 C44,45 47,58 55,41 C61,29 68,48 76,27 C82,13 94,20 112,15';

// A cat built from an actual silhouette: ear notches cut into the skull line,
// a cheek that widens below the eyes, whiskers that start at the muzzle.
const cat = (body, eye, pupil) => `
  <path d="M30,114 L30,74 C30,72 32,71 33,73 L41,83 C46,80 54,78 60,78
           C66,78 74,80 79,83 L87,73 C88,71 90,72 90,74 L90,114 Z" fill="${body}"/>
  <ellipse cx="49" cy="92" rx="5.4" ry="6.2" fill="${eye}"/>
  <ellipse cx="71" cy="92" rx="5.4" ry="6.2" fill="${eye}"/>
  <ellipse cx="49" cy="92.6" rx="1.9" ry="4.6" fill="${pupil}"/>
  <ellipse cx="71" cy="92.6" rx="1.9" ry="4.6" fill="${pupil}"/>
  <path d="M57,102 L63,102 L60,105.5 Z" fill="${eye}"/>
  ${pen('M40,101 L26,98 M40,105 L27,106', 1.5, eye, .8)}
  ${pen('M80,101 L94,98 M80,105 L93,106', 1.5, eye, .8)}`;

const items=[
  { id:'C1', name:'Cat · white', idea:'A cat, not a dome. Ears cut from the skull line.',
    art:`<rect width="120" height="120" fill="#FFFFFF"/>${pen(LINE,5,LIME)}${cat(K, LIME, K)}` },

  { id:'C2', name:'Cat · cream', idea:'Warmer paper, ink line.',
    art:`<rect width="120" height="120" fill="${CREAM}"/>${pen(LINE,5,K)}${cat(K, LIME, K)}` },

  { id:'C3', name:'Cat · violet', idea:'Brand ground, cream cat.',
    art:`<rect width="120" height="120" fill="${VIOLET}"/>${pen(LINE,5,LIME)}${cat(CREAM, K, CREAM)}` },

  { id:'W1', name:'Wordmark', idea:'grug move. Nothing to misread, and it owns the name.',
    art:`<rect width="120" height="120" fill="#FFFFFF"/>
      <text x="60" y="74" text-anchor="middle" fill="${K}"
        style="font:800 40px Allo,ui-rounded,system-ui" letter-spacing="-2.4">pulse</text>
      <circle cx="99" cy="70" r="5.6" fill="${LIME}" stroke="${K}" stroke-width="2.6"/>` },

  { id:'W2', name:'Wordmark · violet', idea:'Same, on the brand.',
    art:`<rect width="120" height="120" fill="${VIOLET}"/>
      <text x="60" y="74" text-anchor="middle" fill="${CREAM}"
        style="font:800 40px Allo,ui-rounded,system-ui" letter-spacing="-2.4">pulse</text>
      <circle cx="99" cy="70" r="5.6" fill="${LIME}" stroke="${CREAM}" stroke-width="2.6"/>` },

  { id:'Q1', name:'Maybe', idea:'A question mark whose dot has already resolved.',
    art:`<rect width="120" height="120" fill="#FFFFFF"/>
      ${pen('M40,44 C40,26 56,18 68,22 C82,27 86,44 74,54 C66,61 62,66 62,76', 11, K)}
      <circle cx="62" cy="96" r="8" fill="${LIME}" stroke="${K}" stroke-width="3.2"/>` },
];

const tile=(c,px)=>`<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
<clipPath id="v${c.id}${px}"><path d="${squircle(120)}"/></clipPath>
<g clip-path="url(#v${c.id}${px})">${c.art}</g></svg>`;

const html=`<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="shared.css"><style>
 body{display:block;margin:0;background:#0B0B0D;font-family:Allo,ui-sans-serif,system-ui,sans-serif;padding:46px}
 h1{color:#fff;text-align:center;font-size:16px;letter-spacing:.15em;font-weight:700;margin:0 0 5px}
 .s{color:#70757D;text-align:center;font-size:12px;margin-bottom:38px}
 .g{display:grid;grid-template-columns:repeat(3,1fr);gap:40px 32px;max-width:900px;margin:0 auto 44px}
 .c{text-align:center}.t{display:flex;align-items:flex-end;justify-content:center;gap:14px;margin-bottom:12px}
 .nm{color:#fff;font-size:13.5px;font-weight:700}.i{color:#868C95;font-size:11.5px;line-height:1.45;margin-top:4px}
 .hs{max-width:400px;margin:0 auto;background:linear-gradient(165deg,#455270,#222937);border-radius:32px;
     padding:26px 24px 30px;display:grid;grid-template-columns:repeat(4,1fr);gap:20px 14px}
 .lb{color:#fff;font-size:9.5px;text-align:center;margin-top:5px}
 .ph{width:60px;height:60px;border-radius:14px;background:rgba(255,255,255,.13);margin:0 auto}
 h2{color:#6E737B;text-align:center;font-size:11px;letter-spacing:.14em;margin:0 0 16px;font-weight:700}
</style></head><body>
<h1>PULSE — ONE MORE PASS</h1><div class="s">168px and 60px</div>
<div class="g">${items.map(c=>`<div class="c"><div class="t">
 <span style="filter:drop-shadow(0 10px 26px rgba(0,0,0,.55))">${tile(c,168)}</span>${tile(c,60)}</div>
 <div class="nm">${c.name}</div><div class="i">${c.idea}</div></div>`).join('')}</div>
<h2>ON A HOME SCREEN</h2>
<div class="hs">${['C1','C3','W1','Q1'].map(id=>{const c=items.find(i=>i.id===id);
 return `<div>${tile(c,60)}<div class="lb">Pulse</div></div>`;}).join('')}
 ${Array.from({length:8}).map(()=>'<div><div class="ph"></div><div class="lb">&nbsp;</div></div>').join('')}</div>
</body></html>`;

fs.writeFileSync('icons7.html',html);
(async()=>{const b=await chromium.launch();
 const p=await b.newPage({viewport:{width:1000,height:980},deviceScaleFactor:2});
 await p.goto('file://'+process.cwd()+'/icons7.html');
 await p.evaluate(()=>document.fonts.ready); await p.waitForTimeout(600);
 await p.screenshot({path:'app-icons-7.png',fullPage:true});await b.close();console.log('ok');})();
