// The accent set as it actually appears: ten market gradients, parsed from
// Palette.swift so this cannot drift from the code.
const { chromium } = require('playwright');
const fs = require('fs');

const src = fs.readFileSync('/home/user/pulseapp/PulseCore/Sources/PulseCore/Design/Palette.swift','utf8');
const block = src.slice(src.indexOf('public static let accents'), src.indexOf('/// The house colour'));
const accents = [...block.matchAll(/Color\(hex: "([0-9A-Fa-f]{6})"\)\s*,?\s*\/\/\s*(\w+)/g)].map(m=>({hex:'#'+m[1],name:m[2]}));
const top = '#' + src.match(/fieldTop = Color\(hex: "([0-9A-Fa-f]{6})"\)/)[1];
if (accents.length !== 10) throw new Error('parsed ' + accents.length + ' accents, expected 10');

const card = a => `
<div style="width:150px">
 <div style="height:250px;border-radius:26px;background:linear-gradient(180deg,${top} 0%,${a.hex}73 58%,${a.hex} 100%);
   box-shadow:0 12px 30px rgba(0,0,0,.6);padding:16px;box-sizing:border-box;color:#fff">
   <div style="font-size:10.5px;font-weight:700;letter-spacing:.09em;opacity:.7">POLITICS</div>
   <div style="font-size:16px;font-weight:800;line-height:1.2;margin-top:8px">Fed cuts rates in March</div>
   <div style="font-size:34px;font-weight:900;margin-top:14px">64%</div>
   <div style="margin-top:auto;position:relative;top:68px">
     <div style="height:34px;border-radius:17px;background:#fff;color:#16121F;display:grid;place-items:center;
       font-size:12.5px;font-weight:800">Buy Yes</div></div>
 </div>
 <div style="color:#fff;font-size:11.5px;text-align:center;margin-top:9px;font-weight:600">${a.name}</div>
 <div style="color:#6E737B;font-size:10px;text-align:center">${a.hex}</div></div>`;

const html = `<!doctype html><html><body style="margin:0;background:#09090A;padding:44px;font-family:system-ui">
<div style="color:#fff;text-align:center;font-size:15px;letter-spacing:.14em;font-weight:700;margin-bottom:6px">MARKET COLOURS</div>
<div style="color:#70757D;text-align:center;font-size:12px;margin-bottom:34px">same gradient, same dark top — one variable changes</div>
<div style="display:flex;flex-wrap:wrap;gap:22px;justify-content:center;max-width:1000px;margin:0 auto">
${accents.map(card).join('')}</div></body></html>`;
fs.writeFileSync('colours.html', html);
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1100,height:800},deviceScaleFactor:2});
 await p.goto('file://'+process.cwd()+'/colours.html');await p.waitForTimeout(300);
 await p.screenshot({path:'market-colours.png',fullPage:true});await b.close();
 console.log('rendered ' + accents.length + ' market colours');})();
