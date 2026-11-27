const fs = require('fs');
const themes = JSON.parse(fs.readFileSync('../themes.json', 'utf8'));
const data = JSON.parse(fs.readFileSync('data.json', 'utf8'));
const ICONS = require('./icons.js');

const hex = h => '#' + h;
// FNV-1a, matching Palette.theme(for:) exactly so a market gets the same
// colour here as it does in the app.
// Derived from the parsed palette, in declaration order, so renaming a
// theme in Swift cannot silently desync the render.
const order = Object.keys(themes);
function themeFor(id) {
  let h = 0xcbf29ce484222325n;
  for (const b of Buffer.from(String(id), 'utf8')) {
    h ^= BigInt(b); h = (h * 0x100000001b3n) & 0xFFFFFFFFFFFFFFFFn;
  }
  return themes[order[Number(h % 8n)]];
}
const pct = p => p == null ? '—' : (p * 100 < 1 ? '<1%' : p * 100 > 99 ? '>99%' : Math.round(p * 100) + '%');
const cents = p => { if (p == null) return '—';
  const raw = Math.round(p * 100);
  // Matches Format.cents: an open market never prices at 0 or 100.
  return (p > 0 && p < 1 ? Math.min(99, Math.max(1, raw)) : raw) + '¢'; };
const money = v => { if (v == null) return '—'; const a = Math.abs(v);
  if (a >= 1e9) return '$' + (a/1e9).toFixed(1) + 'B';
  if (a >= 1e6) return '$' + (a/1e6).toFixed(1) + 'M';
  if (a >= 1e3) return '$' + (a/1e3).toFixed(1) + 'K';
  return '$' + Math.round(a); };
function left(iso) { if (!iso) return ''; const d = (new Date(iso) - new Date()) / 36e5;
  if (d < 0) return 'Closed'; if (d < 24) return Math.max(1, Math.round(d)) + 'h left';
  return Math.round(d / 24) + 'd left'; }

const status = ink => `<div class="status" style="color:${ink}">
  <div style="font-weight:700">9:41</div>
  <div class="right">${ICONS.wifi.replace('<svg','<svg style="width:16px;height:16px"')}
  ${ICONS.battery.replace('<svg','<svg style="width:25px;height:12px"')}</div></div>`;

const tabbar = (on) => `<div class="tabbar glass-dark">
  ${[['house','Home'],['search','Explore'],['pie','Portfolio'],['clock','Activity'],['person','Profile']]
    .map(([i,l],n)=>`<div class="tab ${n===on?'on':''}">${ICONS[i]}<span>${l}</span></div>`).join('')}
</div>`;

const artFor = (e, size, radius) => e.image
  ? `<img class="art" src="${e.image}" style="width:${size}px;height:${size}px;border-radius:${radius}px">`
  : `<div class="art" style="width:${size}px;height:${size}px;border-radius:${radius}px"></div>`;

// ---------- Home ----------
function home() {
  const t = themes.ink;
  const ink = hex(t.onField);
  const CARD = '#FFFFFF', CINK = '#11131A', CSEC = '#61646E', CTER = '#8E919B';
  const YES = '#1B8A5A', YESBG = '#D4EFE0', NO = '#C2365B', NOBG = '#FAD8E1';
  const rows = data.slice(1, 5).map(e => {
    const legs = e.multi ? e.legs.map(l => `
      <div style="display:flex;align-items:center;gap:8px;margin-top:8px">
        <div style="font-size:14px;font-weight:500;color:${CINK};overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1">${l.t}</div>
        <div class="tnum" style="font-size:15px;font-weight:600;color:${CINK}">${pct(l.p)}</div>
        <div style="display:flex;gap:8px;width:176px">
          <div class="pill" style="flex:1;height:34px;background:${YESBG};color:${YES};font-size:12px;justify-content:space-between;padding:0 12px"><span>Yes</span><b class="tnum">${cents(l.p)}</b></div>
          <div class="pill" style="flex:1;height:34px;background:${NOBG};color:${NO};font-size:12px;justify-content:space-between;padding:0 12px"><span>No</span><b class="tnum">${cents(1-l.p)}</b></div>
        </div>
      </div>`).join('') : `
      <div style="margin-top:12px">
        <div style="height:6px;border-radius:999px;background:${CINK}1a;overflow:hidden">
          <div style="height:100%;width:${(e.prob||.5)*100}%;background:${CINK}d9;border-radius:999px"></div></div>
        <div style="display:flex;gap:8px;margin-top:10px">
          <div class="pill" style="flex:1;height:44px;background:${YESBG};color:${YES};font-size:14px;justify-content:space-between;padding:0 14px"><span>Yes</span><b class="tnum">${cents(e.prob)}</b></div>
          <div class="pill" style="flex:1;height:44px;background:${NOBG};color:${NO};font-size:14px;justify-content:space-between;padding:0 14px"><span>No</span><b class="tnum">${cents(1-e.prob)}</b></div>
        </div>
      </div>`;
    return `<div style="background:${CARD};border-radius:28px;padding:16px;margin-bottom:12px;box-shadow:0 8px 18px rgba(0,0,0,.22)">
      <div style="display:flex;gap:12px;align-items:flex-start">
        ${artFor(e, 76, 14)}
        <div style="flex:1;min-width:0">
          <div style="font-size:11px;font-weight:600;letter-spacing:.7px;color:${CTER}">${(e.cat||'MARKET').toUpperCase()}</div>
          <div style="font-size:18px;font-weight:600;line-height:1.22;color:${CINK};margin-top:3px">${e.title}</div>
          <div style="font-size:12px;color:${CSEC};margin-top:4px">${money(e.vol24)} · ${left(e.end)}</div>
        </div>
        ${!e.multi ? `<div class="tnum" style="font-size:22px;font-weight:700;color:${CINK}">${pct(e.prob)}</div>` : ''}
      </div>${legs}</div>`;
  }).join('');

  const cards = data.slice(0, 3).map(e => {
    const ct = themeFor(String(e.title)); const ci = hex(ct.onField);
    return `<div style="width:290px;height:300px;flex:none;background:${hex(ct.screen)};border-radius:34px;padding:16px;display:flex;flex-direction:column;box-shadow:0 10px 24px rgba(0,0,0,.26)">
      <div style="display:flex;justify-content:space-between;align-items:flex-start">
        ${artFor(e, 132, 20)}
        ${!e.multi ? `<div class="tnum" style="font-size:22px;font-weight:700;color:${ci}">${pct(e.prob)}</div>` : ''}
      </div>
      <div style="font-size:21px;font-weight:700;line-height:1.2;color:${ci};margin-top:12px;overflow:hidden">${e.title}</div>
      <div style="flex:1"></div>
      <div style="font-size:12px;color:${ci}99">${money(e.vol24)} · ${left(e.end)}</div></div>`;
  }).join('');

  return `<div class="phone" style="background:${hex(t.screen)}"><div class="island"></div>${status(ink)}
    <div class="scroll">
      <div class="pad" style="display:flex;align-items:center;justify-content:space-between;padding-top:8px;padding-bottom:14px">
        <div><div style="font-size:32px;font-weight:800;color:${ink};letter-spacing:-.6px">Markets</div>
        <div style="font-size:14px;color:${ink}a6;margin-top:1px">What the world is betting on</div></div>
        <div class="pill glass" style="width:42px;height:42px;color:${ink}">${ICONS.bell.replace('<svg','<svg style="width:17px;height:17px"')}</div>
      </div>
      <div class="pad" style="font-size:26px;font-weight:700;color:${ink};margin-bottom:10px">Featured</div>
      <div style="display:flex;gap:12px;padding:0 16px;overflow:hidden">${cards}</div>
      <div class="pad" style="font-size:26px;font-weight:700;color:${ink};margin:22px 0 10px">Trending</div>
      <div class="pad">${rows}</div>
    </div>${tabbar(0)}</div>`;
}

// ---------- Market detail ----------
function detail() {
  const e = data.find(x => !x.multi) || data[3];
  const t = themeFor(String(e.title)); const ink = hex(t.onField);
  const p = e.prob || (e.legs[0] && e.legs[0].p) || .5;
  const book = [[.62,120],[.61,340],[.60,890],[.59,1420]];
  return `<div class="phone" style="background:${hex(t.screen)}"><div class="island"></div>${status(ink)}
   <div class="scroll">
    <div class="pad" style="display:flex;gap:8px;padding-top:4px">
      <div class="pill glass" style="width:38px;height:38px;color:${ink}">${ICONS.back.replace('<svg','<svg style="width:16px;height:16px"')}</div>
    </div>
    <div style="display:flex;flex-direction:column;align-items:center;padding:14px 16px 0">
      ${artFor(e, 190, 34).replace('class="art"','class="art" style_x=""').replace('style="','style="box-shadow:0 18px 40px rgba(0,0,0,.35);')}
      <div style="font-size:26px;font-weight:700;color:${ink};text-align:center;margin-top:18px;line-height:1.18">${e.title}</div>
      <div class="tnum" style="font-size:56px;font-weight:900;color:${ink};margin-top:14px;letter-spacing:-1.5px">${pct(p)}</div>
      <div style="display:flex;gap:10px;align-items:center;font-size:14px;font-weight:500;color:${ink}b3;margin-top:-2px">
        <span>Yes</span><span>+3 pts</span>
        <span style="display:flex;align-items:center;gap:5px"><span style="width:6px;height:6px;border-radius:99px;background:${ink}"></span>Live</span>
      </div>
      <div style="display:flex;gap:8px;margin-top:18px">
        ${['star','bolt','doc','share'].map(i=>`<div class="pill glass" style="width:44px;height:44px;color:${ink}">${ICONS[i].replace('<svg','<svg style="width:17px;height:17px"')}</div>`).join('')}
      </div>
      <div style="display:flex;gap:8px;width:100%;margin-top:20px">
        <div class="pill" style="flex:1;height:56px;background:${hex(t.control)};color:${hex(t.onControl)};font-size:17px;flex-direction:column;gap:1px"><span>Buy Yes</span><span class="tnum" style="font-size:13px;opacity:.75">${cents(p)}</span></div>
        <div class="pill" style="flex:1;height:56px;background:${ink}22;color:${ink};font-size:17px;flex-direction:column;gap:1px"><span>Buy No</span><span class="tnum" style="font-size:13px;opacity:.75">${cents(1-p)}</span></div>
      </div>
      <div style="width:100%;background:${ink}1f;border-radius:28px;padding:16px;margin-top:18px">
        <div style="font-size:11px;font-weight:600;letter-spacing:.8px;color:${ink}80">ORDER BOOK · YES</div>
        ${book.map(([pr,sz],i)=>`<div style="position:relative;height:22px;margin-top:6px;display:flex;align-items:center">
          <div style="position:absolute;left:0;top:0;bottom:0;width:${20+i*22}%;background:${ink}1a;border-radius:4px"></div>
          <div class="tnum" style="position:relative;font-size:13px;font-weight:500;color:${ink};padding-left:6px">${cents(pr)}</div>
          <div style="flex:1"></div>
          <div class="tnum" style="position:relative;font-size:13px;color:${ink}99;padding-right:6px">${sz}</div></div>`).join('')}
      </div>
    </div></div>${tabbar(0)}</div>`;
}

// ---------- Onboarding ----------
function onboarding() {
  const t = themes.lime; const ink = hex(t.onField);
  const price = .35, stake = 10, shares = stake / price;
  return `<div class="phone" style="background:${hex(t.screen)}"><div class="island"></div>${status(ink)}
   <div class="scroll" style="display:flex;flex-direction:column">
    <div class="pad" style="display:flex;align-items:center;justify-content:space-between;padding-top:10px">
      <div style="display:flex;gap:4px;align-items:center">
        <div style="width:7px;height:7px;border-radius:99px;background:${ink}e6"></div>
        <div style="width:22px;height:7px;border-radius:99px;background:${ink}e6"></div>
        <div style="width:7px;height:7px;border-radius:99px;background:${ink}38"></div>
        <div style="width:7px;height:7px;border-radius:99px;background:${ink}38"></div>
      </div>
      <div class="pill glass" style="height:32px;padding:0 14px;color:${ink};font-size:12px">Skip</div>
    </div>
    <div style="flex:1;display:flex;flex-direction:column;justify-content:center;padding:0 16px">
      <div style="text-align:center">
        <div class="tnum" style="font-size:56px;font-weight:900;color:${ink};letter-spacing:-1.5px">${cents(price)}<span style="font-size:15px;font-weight:500;opacity:.6;letter-spacing:0"> per share</span></div>
      </div>
      <div style="height:5px;border-radius:99px;background:${ink}2e;margin:22px 0 6px;position:relative">
        <div style="position:absolute;left:0;top:0;bottom:0;width:33%;background:${ink};border-radius:99px"></div>
        <div style="position:absolute;left:33%;top:50%;transform:translate(-50%,-50%);width:26px;height:26px;border-radius:99px;background:#fff;box-shadow:0 2px 8px rgba(0,0,0,.3)"></div>
      </div>
      <div style="display:flex;gap:12px;margin-top:22px">
        ${[['STAKE','$10.00',0],['SHARES',Math.round(shares),0],['IF RIGHT','$'+shares.toFixed(2),1]]
          .map(([l,v,hl])=>`<div style="flex:1;text-align:center;padding:12px 4px;border-radius:12px;background:${ink}${hl?'29':'12'}">
          <div style="font-size:11px;font-weight:600;letter-spacing:.8px;color:${ink}80">${l}</div>
          <div class="tnum" style="font-size:17px;font-weight:600;color:${ink};margin-top:2px">${v}</div></div>`).join('')}
      </div>
    </div>
    <div style="padding:0 16px 30px">
      <div style="font-size:14px;font-weight:500;color:${ink}8c">How it works</div>
      <div style="font-size:44px;font-weight:900;color:${ink};line-height:1.02;letter-spacing:-1.4px;margin-top:6px">Price is<br>probability.</div>
      <div style="font-size:15px;color:${ink}b3;margin-top:12px;line-height:1.4">A share costs what the market thinks the odds are. If you're right, it settles at $1. Drag to see it.</div>
      <div class="pill" style="width:100%;height:52px;background:${hex(t.control)};color:${hex(t.onControl)};font-size:16px;margin-top:20px">Continue &nbsp;→</div>
    </div></div></div>`;
}


// ---------- Trade sheet ----------
function trade() {
  const e = data.find(x => !x.multi) || data[3];
  const t = themeFor(String(e.title)); const ink = hex(t.onField);
  const price = 0.60, spend = 25, shares = spend / price, fee = 0.15;
  const YES = '#1B8A5A', NO = '#C2365B';
  const panel = (inner, pad) => `<div style="background:${ink}1f;border-radius:28px;padding:${pad||16}px">${inner}</div>`;

  return `<div class="phone" style="background:${hex(t.screen)}"><div class="island"></div>${status(ink)}
   <div class="scroll">
    <div style="display:flex;align-items:center;padding:8px 16px 10px">
      <div style="font-size:14px;font-weight:500;color:${ink}b3">Cancel</div>
      <div style="flex:1;display:flex;justify-content:center"><div style="width:36px;height:5px;border-radius:99px;background:${ink}4d"></div></div>
      <div style="font-size:14px;opacity:0">Cancel</div>
    </div>
    <div style="padding:0 16px;display:flex;flex-direction:column;gap:16px">

      <div style="display:flex;gap:12px;align-items:center">
        ${artFor(e, 52, 13)}
        <div style="font-size:16px;font-weight:600;color:${ink};line-height:1.25">${e.title}</div>
      </div>

      <div style="display:flex;flex-direction:column;gap:12px">
        <div style="display:flex;gap:8px">
          <div class="pill" style="flex:1;height:48px;background:${YES};color:#fff;font-size:16px">Buy</div>
          <div class="pill" style="flex:1;height:48px;background:${ink}1f;color:${ink};font-size:16px">Sell</div>
        </div>
        <div style="display:flex;gap:8px">
          <div class="pill" style="flex:1;height:38px;background:${hex(t.control)};color:${hex(t.onControl)};font-size:14px">Market</div>
          <div class="pill" style="flex:1;height:38px;background:${ink}1f;color:${ink};font-size:14px">Limit</div>
        </div>
      </div>

      ${panel(`
        <div style="display:flex;justify-content:space-between;align-items:baseline">
          <div style="font-size:14px;font-weight:500;color:${ink}b3">You spend</div>
          <div style="font-size:12px;color:${ink}99">$420.00 available</div>
        </div>
        <div class="tnum" style="font-size:38px;font-weight:800;color:${ink};margin-top:8px">$${spend}</div>
        <div style="display:flex;gap:8px;margin-top:14px">
          ${[5,25,100,500].map(v=>`<div class="pill" style="flex:1;height:38px;background:${ink}1f;color:${ink};font-size:14px">$${v}</div>`).join('')}
        </div>`)}

      ${panel(`
        <div style="display:flex;gap:12px">
          <div style="flex:1">
            <div style="font-size:11px;font-weight:600;letter-spacing:.8px;color:${ink}80">YOU GET</div>
            <div class="tnum" style="font-size:22px;font-weight:700;color:${ink};margin-top:2px">${shares.toFixed(0)} sh</div>
            <div style="font-size:12px;color:${ink}8c">est. at ${cents(price)}</div>
          </div>
          <div style="flex:1">
            <div style="font-size:11px;font-weight:600;letter-spacing:.8px;color:${ink}80">IF CORRECT</div>
            <div class="tnum" style="font-size:22px;font-weight:700;color:#8FE3B6;margin-top:2px">$${shares.toFixed(2)}</div>
            <div style="font-size:12px;color:${ink}8c">+$${(shares-spend-fee).toFixed(2)} profit</div>
          </div>
        </div>
        <div style="height:1px;background:${ink}24;margin:14px 0"></div>
        <div style="display:flex;justify-content:space-between;margin-bottom:6px">
          <span style="font-size:14px;color:${ink}b3">Total cost</span>
          <span class="tnum" style="font-size:17px;font-weight:600;color:${ink}">$${(spend+fee).toFixed(2)}</span></div>
        <div style="display:flex;justify-content:space-between;margin-bottom:6px">
          <span style="font-size:14px;color:${ink}b3">Est. fees</span>
          <span class="tnum" style="font-size:13px;color:${ink}">$${fee.toFixed(2)}</span></div>
        <div style="display:flex;justify-content:space-between">
          <span style="font-size:14px;color:${ink}b3">Price impact</span>
          <span class="tnum" style="font-size:13px;color:${ink}">+1.2%</span></div>`)}

      <div style="display:flex;gap:8px;align-items:flex-start;background:${ink}12;border-radius:12px;padding:12px">
        <span style="color:${ink}8c;font-size:13px">ⓘ</span>
        <span style="font-size:12px;color:${ink}99;line-height:1.35">Prediction markets carry risk. Positions can lose their full value.</span>
      </div>
    </div>
    <div style="padding:16px">
      <div class="pill" style="width:100%;height:52px;background:${hex(t.control)};color:${hex(t.onControl)};font-size:16px">Review · $${(spend+fee).toFixed(2)}</div>
    </div>
   </div></div>`;
}

// ---------- Portfolio ----------
function portfolio() {
  const t = themes.ink; const ink = hex(t.onField);
  const CARD='#FFFFFF', CINK='#11131A', CSEC='#61646E', CTER='#8E919B', CSEP='#E6E7EB';
  const YES='#1B8A5A', YESBG='#D4EFE0', NO='#C2365B';
  const pos = [
    {t:'Bitcoin above $54,000 on November 27?', o:'Yes', v:3741.60, p:45.86, sh:3747, avg:.986, now:.998, c:'green', share:.52},
    {t:'Fed Decision in December?', o:'No', v:1280.00, p:-96.20, sh:1600, avg:.86, now:.80, c:'lime', share:.26},
    {t:'Next Prime Minister of Spain?', o:'Yes', v:820.40, p:122.40, sh:1180, avg:.59, now:.70, c:'coral', share:.14},
  ];
  const total = pos.reduce((a,b)=>a+b.v,0);

  const row = q => `<div style="background:${CARD};border-radius:28px;padding:16px;box-shadow:0 8px 18px rgba(0,0,0,.2)">
    <div style="display:flex;gap:12px;align-items:flex-start">
      <div class="art" style="width:48px;height:48px;border-radius:12px;background:${hex(themes[q.c].screen)}"></div>
      <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:600;color:${CINK};line-height:1.25">${q.t}</div>
        <div style="margin-top:6px"><span class="pill" style="background:${q.o==='Yes'?YESBG:'#FAD8E1'};color:${q.o==='Yes'?YES:NO};font-size:12px;padding:3px 10px">${q.o}</span></div>
      </div>
      <div style="text-align:right">
        <div class="tnum" style="font-size:17px;font-weight:600;color:${CINK}">$${q.v.toFixed(2)}</div>
        <div class="tnum" style="font-size:12px;font-weight:500;color:${q.p>=0?YES:NO}">${q.p>=0?'+':'−'}$${Math.abs(q.p).toFixed(2)}</div>
      </div>
    </div>
    <div style="position:relative;height:8px;border-radius:99px;background:${CSEP};margin:12px 0 10px">
      <div style="position:absolute;left:0;top:0;bottom:0;width:${q.now*100}%;border-radius:99px;background:${q.o==='Yes'?YES:NO}d9"></div>
      <div style="position:absolute;left:${q.avg*100}%;top:-2px;width:2px;height:12px;background:${CINK}8c"></div>
    </div>
    <div style="display:flex;gap:20px">
      ${[['SHARES',q.sh],['AVG',cents(q.avg)],['NOW',cents(q.now)]].map(([l,v])=>`<div>
        <div style="font-size:11px;font-weight:600;letter-spacing:.6px;color:${CTER}">${l}</div>
        <div class="tnum" style="font-size:13px;font-weight:500;color:${CSEC}">${v}</div></div>`).join('')}
      <div style="flex:1"></div>
      <div style="text-align:right"><div style="font-size:11px;font-weight:600;letter-spacing:.6px;color:${CTER}">IF WON</div>
      <div class="tnum" style="font-size:13px;font-weight:500;color:${YES}">$${q.sh.toLocaleString()}</div></div>
    </div></div>`;

  return `<div class="phone" style="background:${hex(t.screen)}"><div class="island"></div>${status(ink)}
   <div class="scroll"><div style="padding:8px 16px 0">
     <div style="font-size:32px;font-weight:800;color:${ink};letter-spacing:-.6px">Portfolio</div>
     <div style="font-size:14px;color:${ink}a6">Your positions and P&L</div>
   </div>
   <div style="padding:14px 16px;display:flex;flex-direction:column;gap:16px">
     <div style="background:${ink}1f;border-radius:28px;padding:16px">
       <div style="font-size:11px;font-weight:600;letter-spacing:.9px;color:${ink}80">POSITIONS VALUE</div>
       <div class="tnum" style="font-size:38px;font-weight:800;color:${ink};margin-top:2px">$${total.toLocaleString(undefined,{minimumFractionDigits:2})}</div>
       <div class="tnum" style="font-size:14px;font-weight:500;color:#8FE3B6;margin-top:2px">↗ +$72.06 · +1.3%</div>
       <div style="height:1px;background:${ink}24;margin:14px 0"></div>
       <div style="display:flex;gap:12px">
         ${[['UNREALISED','+$72.06','#8FE3B6'],['REALISED','−$18.40','#F2869F'],['IF ALL CORRECT','$6,527',ink]].map(([l,v,c])=>`<div style="flex:1">
           <div style="font-size:11px;font-weight:600;letter-spacing:.8px;color:${ink}80">${l}</div>
           <div class="tnum" style="font-size:17px;font-weight:600;color:${c}">${v}</div></div>`).join('')}
       </div>
     </div>

     <div style="background:${ink}14;border-radius:28px;padding:16px">
       <div style="display:flex;justify-content:space-between">
         <div style="font-size:11px;font-weight:600;letter-spacing:.9px;color:${ink}80">ALLOCATION</div>
         <div style="font-size:12px;color:${ink}8c">3 positions</div></div>
       <div style="display:flex;gap:2px;height:10px;border-radius:99px;overflow:hidden;margin-top:10px">
         ${pos.map(q=>`<div style="width:${q.share*100}%;background:${hex(themes[q.c].screen)}"></div>`).join('')}
       </div>
       <div style="font-size:12px;color:${ink}8c;margin-top:8px">Largest: Bitcoin above $54,000 · 52%</div>
     </div>

     <div style="display:flex;gap:8px">
       ${['Open','Redeemable','Closed'].map((c,i)=>`<div class="pill" style="height:38px;padding:0 16px;font-size:14px;background:${i===0?ink:ink+'1f'};color:${i===0?hex(t.screen):ink}">${c}</div>`).join('')}
     </div>

     ${pos.map(row).join('')}
   </div></div>${tabbar(2)}</div>`;
}

const page = (title, body) => `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="shared.css"><title>${title}</title></head><body>${body}</body></html>`;

fs.writeFileSync('screens.html', page('Pulse', home() + detail() + onboarding()));
fs.writeFileSync('screens2.html', page('Pulse', trade() + portfolio()));
console.log('wrote screens.html');
