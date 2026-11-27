const fs = require('fs');
const themes = JSON.parse(fs.readFileSync('../themes.json', 'utf8'));
const ICONS = require('./icons.js');
const hex = h => '#' + h;

// Two situations, each shown with glass and with solid.
//  A) something scrolling behind the control
//  B) a flat colour field behind it
const chips = (style) => ['Trending','Politics','Sports','Crypto']
  .map((c,i)=>`<div style="${style(i===0)};height:38px;padding:0 16px;border-radius:999px;
       display:flex;align-items:center;font-family:Allo;font-size:14px;font-weight:500;
       white-space:nowrap">${c}</div>`).join('');

const glassStyle = sel => sel
  ? 'background:#fff;color:#11131A'
  : 'backdrop-filter:blur(22px) saturate(180%);background:rgba(255,255,255,.16);border:.5px solid rgba(255,255,255,.22);color:#fff';
const solidStyle = sel => sel
  ? 'background:#fff;color:#11131A'
  : 'background:rgba(255,255,255,.16);color:#fff';

// Busy backdrop: overlapping cards, as a feed looks under a floating bar.
const busy = `<div style="position:absolute;inset:0;overflow:hidden">
  ${[['coral',10,8,150],['butter',120,70,150],['sky',230,20,150],['lime',40,120,150]]
    .map(([t,x,y,s])=>`<div style="position:absolute;left:${x}px;top:${y}px;width:${s}px;height:${s}px;
         border-radius:24px;background:${hex(themes[t].screen)}"></div>`).join('')}
</div>`;

const panel = (title, bg, backdrop, style) => `
  <div style="width:360px">
    <div style="font-family:Allo;font-size:12px;font-weight:600;color:rgba(255,255,255,.5);
                padding:0 4px 8px">${title}</div>
    <div style="position:relative;height:210px;border-radius:26px;overflow:hidden;background:${bg}">
      ${backdrop}
      <div style="position:absolute;left:0;right:0;bottom:16px;display:flex;gap:8px;padding:0 14px;overflow:hidden">
        ${chips(style)}
      </div>
    </div>
  </div>`;

const html = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="shared.css"></head>
<body style="display:block;background:#0E1116;padding:26px">
  <div style="display:flex;gap:20px;margin-bottom:26px">
    ${panel('A · Content behind — GLASS', hex(themes.ink.screen), busy, glassStyle)}
    ${panel('A · Content behind — SOLID', hex(themes.ink.screen), busy, solidStyle)}
  </div>
  <div style="display:flex;gap:20px">
    ${panel('B · Flat field behind — GLASS', hex(themes.green.screen), '', glassStyle)}
    ${panel('B · Flat field behind — SOLID', hex(themes.green.screen), '', solidStyle)}
  </div>
</body></html>`;
fs.writeFileSync('glass.html', html);
console.log('wrote glass.html');
