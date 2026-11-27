const fs = require('fs');
const themes = JSON.parse(fs.readFileSync('../themes.json', 'utf8'));
const ICONS = require('./icons.js');
const hex = h => '#' + h;
const ACCENT = ['green','sky','lime','coral','lilac'];

// Three candidate sizings, so the choice is made by looking rather than arguing.
const variants = [
  { name: 'Current · 17pt icons, 56pt bar',  icon: 17, selIcon: 15, label: 13, item: 44, pad: 6 },
  { name: 'Larger · 21pt icons, 60pt bar',   icon: 21, selIcon: 19, label: 14, item: 48, pad: 6 },
  { name: 'Largest · 24pt icons, 64pt bar',  icon: 24, selIcon: 21, label: 15, item: 52, pad: 6 },
];

const bar = v => `<div style="position:relative;margin:0 16px">
  <div style="display:flex;align-items:center;gap:4px;padding:${v.pad}px;border-radius:999px;
              background:rgba(14,16,20,.88);border:.5px solid rgba(255,255,255,.1);
              box-shadow:0 10px 24px rgba(0,0,0,.35)">
    ${[['house','Home'],['search','Explore'],['pie','Portfolio'],['swap','Activity'],['person','Profile']]
      .map(([i,l],n)=>{
        const sel = n===0, a = themes[ACCENT[n]];
        const svg = s => ICONS[i].replace('<svg', `<svg style="width:${s}px;height:${s}px;flex:none"`);
        return sel
          ? `<div style="display:flex;align-items:center;gap:6px;height:${v.item}px;padding:0 16px;
                 border-radius:999px;background:${hex(a.screen)};color:${hex(a.onField)};flex:0 0 auto">
               ${svg(v.selIcon)}<span style="font-size:${v.label}px;font-weight:600">${l}</span></div>`
          : `<div style="display:flex;align-items:center;justify-content:center;height:${v.item}px;
                 flex:1 1 0;color:rgba(255,255,255,.62)">${svg(v.icon)}</div>`;
      }).join('')}
  </div></div>`;

const html = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="shared.css"></head>
<body style="display:block;background:#1B2C44;padding:28px 0">
${variants.map(v => `
  <div style="width:393px;margin:0 auto 28px">
    <div style="font-family:Allo;font-size:13px;font-weight:600;color:rgba(255,255,255,.55);
                padding:0 16px 8px">${v.name}</div>
    ${bar(v)}
  </div>`).join('')}
</body></html>`;

fs.writeFileSync('compare.html', html);
console.log('wrote compare.html');
