// Renders the shipping app icon to PNG at 1024, the only size the asset
// catalog needs — iOS derives the rest.
//
// The mark: something peeking over a rising market, paws hooked on the line.
// Drawn rather than constructed, because the reference set it belongs to
// (Bunpo, daplit, Nurio, grug) wins on observation and line work, not on
// bold geometry. Two earlier attempts failed here — a stock heartbeat line,
// then a vector mascot built from perfect circles, which reads as clip art
// in this company.
//
// Contact is the whole trick: without paws over the line the creature floats
// behind it instead of holding on, and the joke disappears.
//
// The tile is square and unmasked. iOS applies its own squircle, and a
// pre-rounded PNG shows pale corners inside it.
const { chromium } = require('playwright');
const fs = require('fs');

const K = '#15161A';
const LIME = '#D9F930';

// Hand-weighted, not plotted: the flats are uneven and the rises differ, so
// it reads as a market rather than a waveform.
const LINE = 'M10,78 C24,77 29,80 39,67 C46,57 49,69 57,53 C63,41 69,60 77,39 C83,24 93,31 110,26';

const variants = {
  day:   { bg:'#FFFFFF', line: LIME, body: K,         ring: false },
  night: { bg:'#15121C', line: LIME, body:'#FFFFFF',  ring: true  },
  plain: { bg:'#FFFFFF', line: K,    body: K,         ring: false },
};

function svg(v, px) {
  return `<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
  <rect width="120" height="120" fill="${v.bg}"/>
  <path d="${LINE}" fill="none" stroke="${v.line}" stroke-width="5"
        stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M36,112 C36,94 47,85 60,85 C73,85 84,94 84,112 Z" fill="${v.body}"/>
  <circle cx="51" cy="98" r="5" fill="#fff"/>
  <circle cx="69" cy="98" r="5" fill="#fff"/>
  <circle cx="52.6" cy="99.2" r="2.2" fill="${K}"/>
  <circle cx="70.6" cy="99.2" r="2.2" fill="${K}"/>
  ${v.ring ? `<circle cx="51" cy="98" r="5" fill="none" stroke="${K}" stroke-width="1.2"/>
              <circle cx="69" cy="98" r="5" fill="none" stroke="${K}" stroke-width="1.2"/>` : ''}
  <path d="M34,86 C34,81 38,79 42,81 C45,82.5 45,87 42,88 L36,89 Z" fill="${v.body}"/>
  <path d="M86,86 C86,81 82,79 78,81 C75,82.5 75,87 78,88 L84,89 Z" fill="${v.body}"/>
</svg>`;
}

(async () => {
  const out = process.argv[2] || 'AppIcon.png';
  const which = process.argv[3] || 'day';
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
