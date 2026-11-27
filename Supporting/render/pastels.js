const fs = require('fs');

// Three pastel treatments. All light fields with deep same-hue ink — the
// variable is how much chroma the field carries, which is exactly what
// separated "washed out" from "sophisticated" in the earlier attempts.
const sets = {
  'A · Soft — low chroma, airy': {
    anchor:'2C3440',
    sage:'CFE0C8', butter:'F3E3B3', sky:'C5DCEC', lilac:'D8D1EC',
    blush:'F2D3CE', clay:'E8D5C4', mist:'CFE2E0', plum:'E2CFDD',
  },
  'B · Sophisticated — real chroma, muted hue': {
    anchor:'262E38',
    sage:'B5D0A6', butter:'EFD98E', sky:'A8CBE6', lilac:'C3B5E8',
    blush:'F0BEB2', clay:'E0C29C', mist:'A6D2CD', plum:'D9B5D2',
  },
  'C · Deep pastel — richest, still soft': {
    anchor:'1F262F',
    sage:'9CC189', butter:'E9CC6C', sky:'8BBBDF', lilac:'AE9BE0',
    blush:'EBA898', clay:'D6AE7E', mist:'8AC4BD', plum:'CFA0C6',
  },
};

// Deep ink of the field's own hue, never black: that is what keeps a
// pastel looking coloured rather than printed on.
const inkFor = hex => {
  let r = parseInt(hex.slice(0,2),16)/255, g = parseInt(hex.slice(2,4),16)/255, b = parseInt(hex.slice(4,6),16)/255;
  const max = Math.max(r,g,b), min = Math.min(r,g,b);
  let h = 0, s = 0; const l = (max+min)/2;
  if (max !== min) {
    const d = max-min;
    s = l > .5 ? d/(2-max-min) : d/(max+min);
    h = max === r ? (g-b)/d + (g<b?6:0) : max === g ? (b-r)/d+2 : (r-g)/d+4;
    h /= 6;
  }
  // Same hue, much darker, slightly richer.
  const L = 0.16, S = Math.min(1, s + 0.25);
  const hue2rgb = (p,q,t) => { if(t<0)t+=1; if(t>1)t-=1;
    if(t<1/6) return p+(q-p)*6*t; if(t<1/2) return q;
    if(t<2/3) return p+(q-p)*(2/3-t)*6; return p; };
  const q = L < .5 ? L*(1+S) : L+S-L*S, p = 2*L-q;
  const to = v => Math.round(v*255).toString(16).padStart(2,'0').toUpperCase();
  return to(hue2rgb(p,q,h+1/3)) + to(hue2rgb(p,q,h)) + to(hue2rgb(p,q,h-1/3));
};

const swatch = (name, hex) => `<div style="flex:1">
  <div style="height:76px;border-radius:14px;background:#${hex};display:flex;align-items:flex-end;
       padding:8px;color:#${inkFor(hex)};font-family:Allo;font-size:11px;font-weight:700">${name}</div>
  <div style="font-family:Allo;font-size:10px;color:rgba(255,255,255,.35);padding:4px 2px 0">#${hex}</div></div>`;

const sample = p => {
  const i = inkFor(p.sage), si = inkFor(p.sky);
  return `<div style="display:flex;gap:12px;margin-top:14px">
    <div style="flex:1;background:#${p.anchor};border-radius:22px;padding:14px">
      <div style="background:#fff;border-radius:16px;padding:12px">
        <div style="font-family:Allo;font-size:10px;font-weight:600;letter-spacing:.7px;color:#8E919B">POLITICS</div>
        <div style="font-family:Allo;font-size:15px;font-weight:600;color:#11131A;margin-top:3px">Will the Fed cut in March?</div>
        <div style="display:flex;gap:6px;margin-top:10px">
          <div style="flex:1;height:32px;border-radius:99px;background:#${p.sage};color:#${i};
               display:flex;align-items:center;justify-content:space-between;padding:0 12px;
               font-family:Allo;font-size:12px;font-weight:600"><span>Yes</span><span>66¢</span></div>
          <div style="flex:1;height:32px;border-radius:99px;background:#${p.blush};color:#${inkFor(p.blush)};
               display:flex;align-items:center;justify-content:space-between;padding:0 12px;
               font-family:Allo;font-size:12px;font-weight:600"><span>No</span><span>35¢</span></div>
        </div></div></div>
    <div style="flex:1;background:#${p.sage};border-radius:22px;padding:14px;color:#${i}">
      <div style="font-family:Allo;font-size:34px;font-weight:900">66%</div>
      <div style="font-family:Allo;font-size:12px;opacity:.7;margin-top:-2px">Yes · +3 pts · Live</div>
      <div style="display:flex;gap:6px;margin-top:12px">
        <div style="flex:1;height:34px;border-radius:99px;background:#${i};color:#${p.sage};
             display:flex;align-items:center;justify-content:center;font-family:Allo;font-size:13px;font-weight:600">Buy Yes</div>
        <div style="flex:1;height:34px;border-radius:99px;background:#${i}24;
             display:flex;align-items:center;justify-content:center;font-family:Allo;font-size:13px;font-weight:600">Buy No</div>
      </div></div>
    <div style="flex:1;background:#${p.sky};border-radius:22px;padding:14px;color:#${si}">
      <div style="font-family:Allo;font-size:11px;font-weight:600;opacity:.6">How it works</div>
      <div style="font-family:Allo;font-size:26px;font-weight:900;line-height:1.05;margin-top:4px">Price is<br>probability.</div>
    </div></div>`;
};

const block = ([name, p]) => `<div style="margin-bottom:32px">
  <div style="font-family:Allo;font-size:15px;font-weight:700;color:#fff;margin-bottom:10px">${name}</div>
  <div style="display:flex;gap:9px">${Object.entries(p).filter(([k])=>k!=='anchor').map(([k,v])=>swatch(k,v)).join('')}</div>
  ${sample(p)}</div>`;

fs.writeFileSync('pastels.html',
  `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="shared.css"></head>
   <body style="display:block;background:#0B0D11;padding:26px">
   ${Object.entries(sets).map(block).join('')}</body></html>`);
console.log('wrote pastels.html');
