// Renders the shipping app icon to PNG at 1024, the only size the asset
// catalog needs — iOS derives the rest.
//
// The mark: a creature in a market. The green level is the probability and
// the eyes sit just above it, so the icon says "a market, alive" rather than
// borrowing the heartbeat line every health app already uses. The wave has
// real amplitude on purpose; shallower, it reads as a progress bar.
//
// The tile is drawn square and unclipped: iOS applies its own mask, and a
// pre-rounded PNG shows pale corners inside it.
const { chromium } = require('playwright');
const fs = require('fs');

const INK = '#141A21';

function waveFill(y, amp) {
  const pts = [];
  for (let x = -14; x <= 134; x += 1.5) {
    pts.push(`${x},${(y + Math.sin(x / 26) * amp).toFixed(2)}`);
  }
  return 'M' + pts.join(' L') + ' L134,134 L-14,134 Z';
}

const variants = {
  // Eyes just above the line — peering over the market.
  submerged: { a:'#F9E9A6', b:'#DEB942', body:'#FBF7EC', eye: INK, y:54, amp:6.5, ey:38 },
  steady:    { a:'#F9E9A6', b:'#DEB942', body:'#FBF7EC', eye: INK, y:76, amp:6,   ey:50 },
  ink:       { a:'#2F3A47', b:'#10151B', body:'#1E2733', eye:'#F3F0E6', y:70, amp:6.5, ey:48 },
};

function svg(v, px) {
  return `<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${v.a}"/><stop offset="1" stop-color="${v.b}"/></linearGradient>
    <linearGradient id="lv" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#86D9A2"/><stop offset="1" stop-color="#36A35E"/></linearGradient>
    <clipPath id="body"><circle cx="60" cy="60" r="49"/></clipPath>
  </defs>
  <rect width="120" height="120" fill="url(#bg)"/>
  <circle cx="60" cy="60" r="49" fill="${v.body}"/>
  <g clip-path="url(#body)"><path d="${waveFill(v.y, v.amp)}" fill="url(#lv)"/></g>
  <ellipse cx="44" cy="${v.ey}" rx="9" ry="12" fill="${v.eye}"/>
  <ellipse cx="76" cy="${v.ey}" rx="9" ry="12" fill="${v.eye}"/>
  <ellipse cx="47" cy="${v.ey - 4}" rx="3.1" ry="3.8" fill="#fff" opacity=".95"/>
  <ellipse cx="79" cy="${v.ey - 4}" rx="3.1" ry="3.8" fill="#fff" opacity=".95"/>
</svg>`;
}

(async () => {
  const out = process.argv[2] || 'AppIcon.png';
  const which = process.argv[3] || 'submerged';
  const v = variants[which];
  if (!v) throw new Error('unknown variant ' + which + '; have: ' + Object.keys(variants).join(', '));

  fs.writeFileSync('_icon.svg', svg(v, 1024));
  fs.writeFileSync('_icon.html', `<!doctype html><html><body style="margin:0">${svg(v, 1024)}</body></html>`);

  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  await p.goto('file://' + process.cwd() + '/_icon.html');
  await p.waitForTimeout(250);
  await p.screenshot({ path: out });
  await b.close();
  console.log('wrote ' + out + ' (' + which + ')');
})();
