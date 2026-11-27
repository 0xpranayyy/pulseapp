// Renders the shipping app icon to PNG at 1024, which is the only size the
// asset catalog needs — iOS derives the rest.
//
// The tile is drawn square and unclipped: iOS applies its own mask, and a
// pre-rounded PNG shows pale corners against it. The squircle used in the
// review sheet was only ever for previewing.
const { chromium } = require('playwright');
const fs = require('fs');

const INK = '#141A21';
const RISE = 'M18,80 L40,80 L54,46 L68,90 L82,38';

const variants = {
  butter: { a:'#F8E9AC', b:'#E0BF54', fg: INK,      dot:'#EFD98E' },
  ink:    { a:'#2C3542', b:'#11161C', fg:'#8FD3A3', dot:'#141A21' },
};

function svg(v, px) {
  return `<svg width="${px}" height="${px}" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="${v.a}"/><stop offset="1" stop-color="${v.b}"/></linearGradient></defs>
  <rect width="120" height="120" fill="url(#g)"/>
  <path d="${RISE}" fill="none" stroke="${v.fg}" stroke-width="14.5"
        stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="82" cy="38" r="11.5" fill="${v.fg}"/>
  <circle cx="82" cy="38" r="4.6" fill="${v.dot}"/>
</svg>`;
}

(async () => {
  const out = process.argv[2] || 'AppIcon.png';
  const which = process.argv[3] || 'butter';
  const v = variants[which];
  if (!v) throw new Error('unknown variant ' + which);

  fs.writeFileSync('_icon.svg', svg(v, 1024));
  fs.writeFileSync('_icon.html',
    `<!doctype html><html><body style="margin:0">${svg(v, 1024)}</body></html>`);

  const b = await chromium.launch();
  const p = await b.newPage({ viewport:{width:1024,height:1024}, deviceScaleFactor:1 });
  await p.goto('file://' + process.cwd() + '/_icon.html');
  await p.waitForTimeout(250);
  await p.screenshot({ path: out, omitBackground: false });
  await b.close();
  console.log('wrote ' + out + ' (' + which + ')');
})();
