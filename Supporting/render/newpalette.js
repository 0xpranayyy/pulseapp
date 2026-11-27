// Palette systems drawn from the Unrot and Picnic references, on real Pulse
// screens. The earlier pastels were chosen against Brink; these two work a
// different way — one saturated hero colour per screen, or a vertical
// gradient, with a single high-contrast accent doing all the pointing.
const { chromium } = require('playwright');
const fs = require('fs');

const SYSTEMS = [
  { id:'V', name:'Vivid',
    note:'Unrot: one saturated hero colour, flat, white cards and a white pill.',
    field:'#3FB92C', fieldTo:'#3FB92C',
    on:'#FFFFFF', card:'#FFFFFF', cardInk:'#132A0E',
    sub:'rgba(255,255,255,.80)', soft:'rgba(255,255,255,.17)',
    cta:'#FFFFFF', ctaInk:'#2E9A1E', accent:'#FFFFFF',
    yes:'#2E9A1E', no:'#D2365A', chip:'rgba(255,255,255,.20)' },

  { id:'G', name:'Gradient',
    note:'Picnic: dark to vivid down the screen, one acid accent, nothing else.',
    field:'#0C0A14', fieldTo:'#B45CD6',
    on:'#FFFFFF', card:'rgba(255,255,255,.09)', cardInk:'#FFFFFF',
    sub:'rgba(255,255,255,.66)', soft:'rgba(255,255,255,.12)',
    cta:'#FFFFFF', ctaInk:'#16121F', accent:'#D9F930',
    yes:'#D9F930', no:'#FF7A9C', chip:'rgba(255,255,255,.13)' },

  { id:'H', name:'Vivid + depth',
    note:'Saturated hero with the gradient keeping it from going flat, acid accent.',
    field:'#1B8F3A', fieldTo:'#56D16A',
    on:'#FFFFFF', card:'#FFFFFF', cardInk:'#10240F',
    sub:'rgba(255,255,255,.82)', soft:'rgba(255,255,255,.18)',
    cta:'#E8FF4D', ctaInk:'#14300F', accent:'#E8FF4D',
    yes:'#15803D', no:'#C62B50', chip:'rgba(255,255,255,.20)' },
];

const bar = (s, pct) => `
  <div style="height:9px;border-radius:9px;background:${s.soft};overflow:hidden">
    <div style="width:${pct}%;height:100%;border-radius:9px;background:${s.accent}"></div></div>`;

function detail(s) { return `
<div class="phone" style="background:linear-gradient(180deg,${s.field},${s.fieldTo});color:${s.on}">
  <div class="status" style="color:${s.on}"><span>9:41</span><span class="right">▪▪▪ ◗ ▰</span></div>
  <div style="padding:6px 22px 0;display:flex;justify-content:space-between;align-items:center">
    <div style="width:38px;height:38px;border-radius:19px;background:${s.soft};display:grid;place-items:center;font-size:17px">‹</div>
    <div style="display:flex;gap:8px">
      <div style="width:38px;height:38px;border-radius:19px;background:${s.soft};display:grid;place-items:center;font-size:14px">☆</div>
      <div style="width:38px;height:38px;border-radius:19px;background:${s.soft};display:grid;place-items:center;font-size:14px">↗</div></div>
  </div>
  <div style="padding:20px 22px 0">
    <div style="font-size:12px;font-weight:700;letter-spacing:.09em;color:${s.sub};text-transform:uppercase">Politics · closes Mar 4</div>
    <div style="font-size:31px;font-weight:800;line-height:1.1;margin-top:11px;letter-spacing:-.02em">Will the Fed cut rates in March?</div>
    <div style="display:flex;align-items:baseline;gap:10px;margin-top:22px">
      <div style="font-size:62px;font-weight:900;letter-spacing:-.035em;line-height:1">64<span style="font-size:30px">%</span></div>
      <div style="font-size:15px;font-weight:700;color:${s.accent};padding-bottom:9px">▲ 6 today</div>
    </div>
    <div style="margin-top:16px">${bar(s,64)}</div>
  </div>
  <div style="margin:26px 22px 0;background:${s.card};border-radius:26px;padding:20px;color:${s.cardInk}">
    <div style="display:flex;justify-content:space-between;font-size:13px;font-weight:700;opacity:.55">
      <span>ORDER BOOK</span><span>$2.4M vol</span></div>
    ${[['0.64','12,400'],['0.63','8,910'],['0.62','21,050']].map(([p,q],i)=>`
      <div style="display:flex;justify-content:space-between;margin-top:${i?10:14}px;font-size:16px;font-weight:700">
        <span style="color:${s.yes}">${p}</span><span style="opacity:.6">${q}</span></div>`).join('')}
  </div>
  <div style="position:absolute;left:22px;right:22px;bottom:34px;display:flex;gap:11px">
    <div style="flex:1;height:58px;border-radius:29px;background:${s.cta};color:${s.ctaInk};
      display:grid;place-items:center;font-size:17px;font-weight:800">Buy Yes · 64¢</div>
    <div style="flex:1;height:58px;border-radius:29px;background:${s.soft};border:1.5px solid ${s.soft};
      display:grid;place-items:center;font-size:17px;font-weight:800;color:${s.on}">Buy No · 36¢</div>
  </div>
</div>`; }

function feed(s) { return `
<div class="phone" style="background:linear-gradient(180deg,${s.field},${s.fieldTo});color:${s.on}">
  <div class="status" style="color:${s.on}"><span>9:41</span><span class="right">▪▪▪ ◗ ▰</span></div>
  <div style="padding:10px 22px 0">
    <div style="font-size:33px;font-weight:900;letter-spacing:-.03em">Markets</div>
    <div style="margin-top:15px;height:46px;border-radius:23px;background:${s.soft};
      display:flex;align-items:center;padding:0 18px;font-size:15px;color:${s.sub}">Search markets</div>
    <div style="display:flex;gap:8px;margin-top:14px">
      ${['Trending','Politics','Crypto','Sport'].map((t,i)=>`
        <div style="padding:9px 16px;border-radius:19px;font-size:13.5px;font-weight:700;
          background:${i?s.chip:s.accent};color:${i?s.on:(s.accent==='#FFFFFF'?s.ctaInk:'#14300F')}">${t}</div>`).join('')}
    </div>
  </div>
  <div style="padding:16px 22px 0;display:flex;flex-direction:column;gap:13px">
    ${[['Fed cuts rates in March',64,'$2.4M'],['Bitcoin above $150k by June',38,'$8.1M'],
       ['Oscars: Best Picture',71,'$940K']].map(([t,p,v])=>`
      <div style="background:${s.card};border-radius:24px;padding:18px;color:${s.cardInk}">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:14px">
          <div style="font-size:17px;font-weight:800;line-height:1.25;flex:1">${t}</div>
          <div style="font-size:27px;font-weight:900;letter-spacing:-.02em">${p}%</div></div>
        <div style="margin-top:13px;height:8px;border-radius:8px;background:${s.cardInk}1A;overflow:hidden">
          <div style="width:${p}%;height:100%;border-radius:8px;background:${s.yes}"></div></div>
        <div style="margin-top:12px;display:flex;gap:9px">
          <div style="flex:1;height:40px;border-radius:20px;background:${s.yes};color:#fff;
            display:grid;place-items:center;font-size:14.5px;font-weight:800">Yes ${p}¢</div>
          <div style="flex:1;height:40px;border-radius:20px;background:${s.no};color:#fff;
            display:grid;place-items:center;font-size:14.5px;font-weight:800">No ${100-p}¢</div></div>
        <div style="margin-top:11px;font-size:12.5px;font-weight:600;opacity:.5">${v} volume</div>
      </div>`).join('')}
  </div>
</div>`; }

const html = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="shared.css"><style>
 body{display:block;background:#08080A;padding:40px}
 h1{color:#fff;text-align:center;font-size:17px;letter-spacing:.14em;font-weight:700;margin:0 0 34px}
 .sys{margin-bottom:46px}
 .hd{max-width:1240px;margin:0 auto 16px;padding-left:4px}
 .nm{color:#fff;font-size:20px;font-weight:800}
 .nt{color:#8A9099;font-size:13px;margin-top:3px}
 .pair{display:flex;gap:24px;justify-content:center}
 .phone{width:393px;height:852px;border-radius:54px;overflow:hidden;position:relative;flex:none;
   box-shadow:0 20px 56px rgba(0,0,0,.65)}
</style></head><body>
<h1>PALETTE SYSTEMS — FROM YOUR REFERENCES</h1>
${SYSTEMS.map(s=>`<div class="sys">
  <div class="hd"><div class="nm">${s.id} · ${s.name}</div><div class="nt">${s.note}</div></div>
  <div class="pair">${feed(s)}${detail(s)}</div></div>`).join('')}
</body></html>`;

fs.writeFileSync('newpalette.html', html);
(async()=>{const b=await chromium.launch();
 const p=await b.newPage({viewport:{width:900,height:1000},deviceScaleFactor:2});
 await p.goto('file://'+process.cwd()+'/newpalette.html');
 await p.evaluate(()=>document.fonts.ready); await p.waitForTimeout(700);
 const sys=await p.locator('.sys').all();
 for(let i=0;i<sys.length;i++) await sys[i].screenshot({path:`palette-${SYSTEMS[i].id}.png`});
 await b.close(); console.log('rendered '+sys.length+' systems');})();
