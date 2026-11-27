const fs = require('fs');
const themes = JSON.parse(fs.readFileSync('../themes.json', 'utf8'));
const hex = h => '#' + h;
const cents = p => Math.min(99, Math.max(1, Math.round(p*100))) + '¢';
const pct = p => Math.round(p*100) + '%';

const rail = (t, i) => `<div style="display:flex;gap:5px;align-items:center">
  ${[0,1,2,3].map(n=>`<div style="width:${n===i?26:8}px;height:8px;border-radius:99px;
    background:${hex(t.onField)}${n<=i?'f2':'38'}"></div>`).join('')}</div>`;

const chrome = (t, i, body, cta, note) => `<div class="phone" style="background:${hex(t.screen)}">
  <div class="island"></div>
  <div class="status" style="color:${hex(t.onField)}"><div style="font-weight:700">9:41</div></div>
  <div class="scroll" style="display:flex;flex-direction:column">
    <div style="display:flex;align-items:center;justify-content:space-between;padding:10px 16px 0">
      ${rail(t,i)}
      ${i<3?`<div style="height:32px;padding:0 14px;border-radius:99px;display:flex;align-items:center;
        background:${hex(t.onField)}24;color:${hex(t.onField)};font-size:12px;font-weight:600">Skip</div>`:''}
    </div>
    <div style="flex:1;display:flex;align-items:center;justify-content:center;padding:0 16px">${body}</div>
    <div style="padding:0 16px 30px">${cta}</div>
  </div></div>`;

const text = (t, eyebrow, head, body) => `<div style="padding:0 16px 8px">
  <div style="font-size:14px;font-weight:500;color:${hex(t.onField)}8c">${eyebrow}</div>
  <div style="font-size:44px;font-weight:900;color:${hex(t.onField)};line-height:1.02;
       letter-spacing:-1.4px;margin-top:6px;white-space:pre-line">${head}</div>
  <div style="font-size:15px;color:${hex(t.onField)}b3;margin-top:12px;line-height:1.4">${body}</div>
  <div style="margin-top:20px;height:52px;border-radius:99px;display:flex;align-items:center;
       justify-content:center;gap:8px;background:${hex(t.control)};color:${hex(t.onControl)};
       font-size:16px;font-weight:600">Continue  →</div></div>`;

// 1 — fan of market cards
const card = (t, title, p, rot, dx, dy, sc) => `<div style="position:absolute;
  transform:translate(${dx}px,${dy}px) rotate(${rot}deg) scale(${sc});
  width:180px;height:130px;border-radius:22px;background:${hex(t.onField)};padding:14px;
  box-shadow:0 14px 30px rgba(0,0,0,.28);box-sizing:border-box">
  <div style="display:flex;gap:8px;align-items:center">
    <div style="width:26px;height:26px;border-radius:7px;background:${hex(t.screen)}38"></div>
    <div style="font-size:13px;font-weight:600;color:${hex(t.screen)}e6">${title}</div></div>
  <div style="font-size:30px;font-weight:900;color:${hex(t.screen)};margin-top:10px">${pct(p)}</div>
  <div style="height:5px;border-radius:99px;background:${hex(t.screen)}26;margin-top:10px">
    <div style="height:100%;width:${p*100}%;border-radius:99px;background:${hex(t.screen)}d9"></div></div></div>`;

const p1 = (() => { const t = themes.ink; return chrome(t, 0,
  `<div style="position:relative;width:100%;height:230px;display:flex;align-items:center;justify-content:center">
     ${card(t,'Rate cut in March',.18,-15,-58,30,.80)}
     ${card(t,'Who wins the final',.74,13,62,18,.82)}
     ${card(t,'BTC above $100k',.61,-2,0,-16,1)}
   </div>`,
  text(t,'Pulse','Trade what\nyou think\nwill happen.','Real-money markets on elections, sport, crypto and the news — priced by everyone trading them.')); })();

// 2 — payout
const p2 = (() => { const t = themes.lime, price=.35, stake=10, sh=stake/price;
  const tile=(l,v,hl)=>`<div style="flex:1;text-align:center;padding:12px 4px;border-radius:12px;
    background:${hex(t.onField)}${hl?'33':'14'}">
    <div style="font-size:11px;font-weight:600;letter-spacing:.8px;color:${hex(t.onField)}80">${l}</div>
    <div style="font-size:17px;font-weight:700;color:${hex(t.onField)};margin-top:3px">${v}</div></div>`;
  return chrome(t, 1,
  `<div style="width:100%">
     <div style="text-align:center"><span style="font-size:60px;font-weight:900;color:${hex(t.onField)}">${cents(price)}</span>
       <span style="font-size:14px;color:${hex(t.onField)}99"> per share</span></div>
     <div style="position:relative;height:32px;margin:22px 0 18px">
       <div style="position:absolute;top:11px;left:0;right:0;height:10px;border-radius:99px;background:${hex(t.onField)}29"></div>
       <div style="position:absolute;top:11px;left:0;width:35%;height:10px;border-radius:99px;background:${hex(t.onField)}"></div>
       <div style="position:absolute;top:1px;left:calc(35% - 15px);width:30px;height:30px;border-radius:99px;
            background:${hex(t.screen)};border:4px solid ${hex(t.onField)};box-sizing:border-box;
            box-shadow:0 3px 8px rgba(0,0,0,.25)"></div></div>
     <div style="display:flex;gap:8px;align-items:center">
       ${tile('STAKE','$10.00')}<span style="color:${hex(t.onField)}66">→</span>
       ${tile('SHARES',Math.round(sh))}<span style="color:${hex(t.onField)}66">→</span>
       ${tile('IF RIGHT','$'+sh.toFixed(2),1)}</div></div>`,
  text(t,'How it works','Price is\nprobability.',"A share costs what the market thinks the odds are. If you're right, it settles at $1. Drag it.")); })();

// 3 — live book
const p3 = (() => { const t = themes.teal;
  const row=(pr,w,tint,right)=>`<div style="position:relative;height:22px;margin-bottom:5px">
    <div style="position:absolute;${right?'right':'left'}:0;top:0;bottom:0;width:${w*100}%;
         border-radius:6px;background:${tint}e0"></div>
    <div style="position:absolute;inset:0;display:flex;align-items:center;padding:0 10px;
         justify-content:${right?'flex-end':'flex-start'};font-size:13px;font-weight:600;
         color:${hex(t.onField)}">${cents(pr)}</div></div>`;
  return chrome(t, 2,
  `<div style="width:100%">
     ${row(.66,.62,'#E03A60',1)}${row(.65,.38,'#E03A60',1)}${row(.64,.74,'#E03A60',1)}${row(.63,.50,'#E03A60',1)}
     <div style="display:flex;justify-content:space-between;padding:4px 0 7px">
       <span style="font-size:11px;font-weight:600;letter-spacing:1px;color:${hex(t.onField)}73">SPREAD</span>
       <span style="font-size:13px;font-weight:700;color:${hex(t.onField)}b3">1¢</span></div>
     ${row(.62,.42,'#0FA45C')}${row(.61,.66,'#0FA45C')}${row(.60,.88,'#0FA45C')}${row(.59,.55,'#0FA45C')}
   </div>`,
  text(t,'Live','Books that\nmove every\nsecond.','Streaming prices, the full order book, and a chart going back to the day each market opened.')); })();

// 4 — settlement
const p4 = (() => { const t = themes.coral; return chrome(t, 3,
  `<div style="width:100%">
     <div style="display:flex;gap:8px;height:178px">
       <div style="width:52%;border-radius:20px;background:${hex(t.onField)};display:flex;
            align-items:center;justify-content:center;font-size:40px;font-weight:900;color:${hex(t.screen)}">$1</div>
       <div style="flex:1;border-radius:20px;background:${hex(t.onField)}29;display:flex;
            align-items:center;justify-content:center;font-size:40px;font-weight:900;color:${hex(t.onField)}8c">$0</div>
     </div>
     <div style="text-align:center;font-size:12px;color:${hex(t.onField)}99;margin-top:14px">
       One of these happens. The other is worth nothing.</div></div>`,
  `<div style="padding:0 16px 8px">
     <div style="font-size:14px;font-weight:500;color:${hex(t.onField)}8c">Before you start</div>
     <div style="font-size:44px;font-weight:900;color:${hex(t.onField)};line-height:1.02;
          letter-spacing:-1.4px;margin-top:6px;white-space:pre-line">Know the\nrisk.</div>
     <div style="font-size:15px;color:${hex(t.onField)}b3;margin-top:12px;line-height:1.4">A position can lose its whole value. Prices come from other traders, not from a forecast — and nothing here is advice.</div>
     <div style="margin-top:20px;height:52px;border-radius:99px;display:flex;align-items:center;
          justify-content:center;gap:8px;background:${hex(t.control)};color:${hex(t.onControl)};
          font-size:16px;font-weight:600">Start browsing  ↗</div>
     <div style="text-align:center;font-size:12px;color:${hex(t.onField)}99;margin-top:12px">
       You can browse every market without an account.</div></div>`); })();

fs.writeFileSync('onboarding.html',
  `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="shared.css"></head>
   <body>${p1}${p2}${p3}${p4}</body></html>`);
console.log('wrote onboarding.html');
