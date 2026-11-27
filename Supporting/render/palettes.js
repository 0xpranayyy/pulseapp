const fs = require('fs');

// Three candidate palettes, same eight roles, so the choice is about hue
// treatment rather than layout.
const sets = {
  'A · Current — muted': {
    ink:'1B2C44', green:'2A9159', lime:'C3CF3C', sky:'4C8FCB',
    lilac:'8073CE', coral:'D9704F', butter:'E6C463', teal:'35959C',
  },
  'B · Clean — saturated, no grey': {
    ink:'152238', green:'15A95C', lime:'C9DB1E', sky:'2E7BE8',
    lilac:'7C5CE0', coral:'F2623F', butter:'F0B429', teal:'10A3A8',
  },
  'C · Deep — clean but darker': {
    ink:'111C2E', green:'0E8A4A', lime:'A8BC14', sky:'2563C9',
    lilac:'6446BE', coral:'D44A28', butter:'CE941A', teal:'0A8288',
  },
};

// Dark ink needs light text; bright lime and butter need dark.
const inkFor = hex => {
  const r = parseInt(hex.slice(0,2),16), g = parseInt(hex.slice(2,4),16), b = parseInt(hex.slice(4,6),16);
  // Rec. 709 luma — good enough to pick a text colour.
  return (0.2126*r + 0.7152*g + 0.0722*b) > 150 ? '1A1A12' : 'FFFFFF';
};

const swatch = (name, hex) => `<div style="flex:1">
  <div style="height:86px;border-radius:16px;background:#${hex};display:flex;align-items:flex-end;
       padding:8px;color:#${inkFor(hex)};font-family:Allo;font-size:11px;font-weight:600">${name}</div>
  <div style="font-family:Allo;font-size:10px;color:rgba(255,255,255,.4);padding:5px 2px 0">#${hex}</div>
</div>`;

// A card and a chip row in each palette, so the colours are judged doing
// the job rather than as abstract squares.
const sample = p => {
  const i = inkFor(p.green);
  return `<div style="display:flex;gap:12px;margin-top:14px">
    <div style="flex:1;background:#${p.ink};border-radius:22px;padding:14px">
      <div style="background:#fff;border-radius:16px;padding:12px">
        <div style="font-family:Allo;font-size:10px;font-weight:600;letter-spacing:.7px;color:#8E919B">ESPORTS</div>
        <div style="font-family:Allo;font-size:15px;font-weight:600;color:#11131A;margin-top:3px">Will BTC close above $100k?</div>
        <div style="display:flex;gap:6px;margin-top:10px">
          <div style="flex:1;height:32px;border-radius:99px;background:#D4EFE0;color:#1B8A5A;
               display:flex;align-items:center;justify-content:space-between;padding:0 12px;
               font-family:Allo;font-size:12px;font-weight:600"><span>Yes</span><span>66¢</span></div>
          <div style="flex:1;height:32px;border-radius:99px;background:#FAD8E1;color:#C2365B;
               display:flex;align-items:center;justify-content:space-between;padding:0 12px;
               font-family:Allo;font-size:12px;font-weight:600"><span>No</span><span>35¢</span></div>
        </div></div></div>
    <div style="flex:1;background:#${p.green};border-radius:22px;padding:14px;color:#${i}">
      <div style="font-family:Allo;font-size:34px;font-weight:900">66%</div>
      <div style="font-family:Allo;font-size:12px;opacity:.75;margin-top:-2px">Yes · +3 pts · Live</div>
      <div style="display:flex;gap:6px;margin-top:12px">
        <div style="flex:1;height:34px;border-radius:99px;background:#${i};color:#${p.green};
             display:flex;align-items:center;justify-content:center;font-family:Allo;font-size:13px;font-weight:600">Buy Yes</div>
        <div style="flex:1;height:34px;border-radius:99px;background:#${i}29;
             display:flex;align-items:center;justify-content:center;font-family:Allo;font-size:13px;font-weight:600">Buy No</div>
      </div></div>
    <div style="flex:1;background:#${p.lime};border-radius:22px;padding:14px;color:#${inkFor(p.lime)}">
      <div style="font-family:Allo;font-size:11px;font-weight:600;opacity:.6">How it works</div>
      <div style="font-family:Allo;font-size:26px;font-weight:900;line-height:1.05;margin-top:4px">Price is<br>probability.</div>
    </div></div>`;
};

const block = ([name, p]) => `<div style="margin-bottom:34px">
  <div style="font-family:Allo;font-size:15px;font-weight:700;color:#fff;margin-bottom:10px">${name}</div>
  <div style="display:flex;gap:10px">${Object.entries(p).map(([k,v])=>swatch(k,v)).join('')}</div>
  ${sample(p)}
</div>`;

fs.writeFileSync('palettes.html',
  `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="shared.css"></head>
   <body style="display:block;background:#0B0D11;padding:28px">
   ${Object.entries(sets).map(block).join('')}</body></html>`);
console.log('wrote palettes.html');
