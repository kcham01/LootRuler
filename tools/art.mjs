// Draws LootRuler's logo and the README banner with headless Chromium:
//   node tools/art.mjs [screen picture for the banner]
// Writes docs/logo.png (512 x 512), docs/logo-1024.png, docs/banner.png (1280 x 640), and the addon's own
// icon LootRuler/Media/Logo.tga (64 x 64, for the AddOns list, the minimap button and the window).
// The logo: a loot chest under a gold crown whose jewels are the game's item quality colours.
// The banner shows a real screen from the UI test (build/shots/04-reserve.png by default).
import fs from 'node:fs';
import path from 'node:path';

let chromium;
try { ({ chromium } = await import('playwright')); } catch { ({ chromium } = await import('/opt/node-tools/node_modules/playwright/index.mjs')); }
const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const shotPath = path.resolve(process.argv[2] || path.join(root, 'build/shots/04-reserve.png'));
const b64 = f => fs.readFileSync(f).toString('base64');
const font = f => `url(data:font/woff2;base64,${b64(path.join(root, 'node_modules/@fontsource', f))})`;

export const LOGO = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <radialGradient id="bg" cx="50%" cy="42%" r="70%">
      <stop offset="0" stop-color="#2a1640"/><stop offset=".55" stop-color="#140c1c"/><stop offset="1" stop-color="#07050a"/>
    </radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff2b0"/><stop offset=".35" stop-color="#ffd100"/><stop offset=".75" stop-color="#c98a00"/><stop offset="1" stop-color="#7a4f00"/>
    </linearGradient>
    <linearGradient id="goldSide" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#9a6a00"/><stop offset=".5" stop-color="#ffe066"/><stop offset="1" stop-color="#9a6a00"/>
    </linearGradient>
    <linearGradient id="wood" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#8a5228"/><stop offset="1" stop-color="#3a1e0c"/>
    </linearGradient>
    <linearGradient id="lid" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#a5672f"/><stop offset="1" stop-color="#5a3216"/>
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#ffd100" stop-opacity=".55"/><stop offset="1" stop-color="#ffd100" stop-opacity="0"/>
    </radialGradient>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="6"/></filter>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="8" stdDeviation="8" flood-color="#000" flood-opacity=".7"/></filter>
  </defs>
  <rect x="8" y="8" width="496" height="496" rx="84" fill="url(#bg)"/>
  <rect x="26" y="26" width="460" height="460" rx="68" fill="none" stroke="#a335ee" stroke-width="10" opacity=".45" filter="url(#soft)"/>
  <rect x="26" y="26" width="460" height="460" rx="68" fill="none" stroke="#a335ee" stroke-width="5"/>
  <ellipse cx="256" cy="300" rx="190" ry="150" fill="url(#glow)"/>
  <!-- the chest -->
  <g filter="url(#shadow)">
    <path d="M118 262 Q118 196 256 196 Q394 196 394 262 Z" fill="url(#lid)" stroke="#2a1406" stroke-width="6"/>
    <rect x="118" y="262" width="276" height="150" rx="10" fill="url(#wood)" stroke="#2a1406" stroke-width="6"/>
    <path d="M124 278 H388" stroke="#ffd100" stroke-opacity=".9" stroke-width="5"/>
    <rect x="150" y="200" width="26" height="212" fill="url(#goldSide)" stroke="#5a3a00" stroke-width="3"/>
    <rect x="336" y="200" width="26" height="212" fill="url(#goldSide)" stroke="#5a3a00" stroke-width="3"/>
    <rect x="118" y="252" width="276" height="22" fill="url(#gold)" stroke="#5a3a00" stroke-width="3"/>
    <rect x="228" y="262" width="56" height="66" rx="8" fill="url(#gold)" stroke="#5a3a00" stroke-width="4"/>
    <circle cx="256" cy="289" r="8" fill="#2a1406"/><rect x="252" y="292" width="8" height="18" rx="3" fill="#2a1406"/>
  </g>
  <!-- the crown, its jewels in the item quality colours -->
  <g filter="url(#shadow)">
    <path d="M150 178 L136 76 L196 124 L256 56 L316 124 L376 76 L362 178 Z" fill="url(#gold)" stroke="#5a3a00" stroke-width="6" stroke-linejoin="round"/>
    <rect x="146" y="168" width="220" height="28" rx="6" fill="url(#gold)" stroke="#5a3a00" stroke-width="5"/>
    <circle cx="136" cy="72" r="13" fill="#1eff00" stroke="#0a4a00" stroke-width="4"/>
    <circle cx="256" cy="50" r="16" fill="#ff8000" stroke="#5a2a00" stroke-width="4"/>
    <circle cx="376" cy="72" r="13" fill="#0070dd" stroke="#00264a" stroke-width="4"/>
    <circle cx="256" cy="182" r="10" fill="#a335ee" stroke="#3a0a5a" stroke-width="3"/>
    <circle cx="200" cy="182" r="7" fill="#0070dd" stroke="#00264a" stroke-width="3"/>
    <circle cx="312" cy="182" r="7" fill="#1eff00" stroke="#0a4a00" stroke-width="3"/>
    <path d="M248 46 l4 -4" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity=".8"/>
  </g>
  <!-- glints -->
  <g fill="#fff6c8">
    <path d="M412 168 l6 -18 6 18 18 6 -18 6 -6 18 -6 -18 -18 -6z" opacity=".9"/>
    <path d="M96 330 l4 -12 4 12 12 4 -12 4 -4 12 -4 -12 -12 -4z" opacity=".7"/>
  </g>
</svg>`;

const banner = () => `<!doctype html><html><head><style>
@font-face { font-family: Cinzel; font-weight: 700; src: ${font('cinzel/files/cinzel-latin-700-normal.woff2')}; }
@font-face { font-family: Inter; font-weight: 400; src: ${font('inter/files/inter-latin-400-normal.woff2')}; }
@font-face { font-family: Inter; font-weight: 700; src: ${font('inter/files/inter-latin-700-normal.woff2')}; }
html,body{margin:0;width:1280px;height:640px;overflow:hidden;background:#06040a}
.b{position:relative;width:1280px;height:640px;box-sizing:border-box;padding:64px 80px;
 background: radial-gradient(ellipse at 80% 35%, rgba(163,53,238,.38), transparent 55%), radial-gradient(ellipse at 10% 90%, rgba(255,128,0,.16), transparent 50%),
 radial-gradient(circle at 45% 0%, rgba(255,209,0,.10), transparent 40%), linear-gradient(160deg,#120a1c,#06040a 70%);}
.stars{position:absolute;inset:0;background-image:radial-gradient(1px 1px at 20% 30%,#fff8,transparent),radial-gradient(1px 1px at 62% 12%,#fff6,transparent),radial-gradient(1.5px 1.5px at 52% 70%,#fff7,transparent),radial-gradient(1px 1px at 38% 84%,#fff5,transparent),radial-gradient(1px 1px at 8% 58%,#fff6,transparent)}
.left{position:relative;width:660px}
.top{display:flex;align-items:center;gap:22px}
.top svg{width:112px;height:112px;filter:drop-shadow(0 10px 18px rgba(0,0,0,.7))}
.tag{font:700 19px Inter;letter-spacing:.18em;color:#c48cff;text-transform:uppercase;margin-bottom:4px}
h1{margin:0;font:700 84px Cinzel;color:#ffd100;text-shadow:0 3px 0 #000,0 0 34px rgba(255,209,0,.3);line-height:1}
p{margin:26px 0 24px;font:400 28px/1.38 Inter;color:#ece4d4}
.cmds{display:flex;gap:12px;align-items:center}
.cmd{display:inline-block;font:700 24px Consolas,monospace;color:#1eff00;background:rgba(0,0,0,.6);padding:9px 16px;border-radius:6px;box-shadow:inset 0 0 0 2px #2e5a2a}
.chips{display:flex;flex-wrap:wrap;gap:10px;margin-top:22px;width:640px}
.chip{font:700 18px Inter;padding:7px 15px;border-radius:20px;background:rgba(0,0,0,.5);box-shadow:inset 0 0 0 2px #6b4a1c;color:#ffd100}
.shot{position:absolute;right:70px;top:46px;width:388px;transform:rotate(2.5deg);border-radius:12px;
 box-shadow:0 0 0 2px #000,0 30px 70px rgba(0,0,0,.85),0 0 60px rgba(163,53,238,.35)}
</style></head><body><div class="b"><div class="stars"></div>
<div class="left">
  <div class="top">${LOGO}<div><div class="tag">In-game addon - TBC Anniversary</div><h1>LootRuler</h1></div></div>
  <p>Soft reserves inside World of Warcraft. Pick the raid, reserve in game or by whisper, and send it all to Gargul.</p>
  <div class="cmds"><span class="cmd">/lr</span><span class="cmd" style="color:#ff8bd8;box-shadow:inset 0 0 0 2px #5a2a4a">!lr [item]</span></div>
  <div class="chips"><span class="chip" style="color:#a335ee;box-shadow:inset 0 0 0 2px #4a1f6a">Soft &amp; hard reserves</span><span class="chip" style="color:#ff8000;box-shadow:inset 0 0 0 2px #6a3a10">Gargul import</span><span class="chip" style="color:#1eff00;box-shadow:inset 0 0 0 2px #1f5a1a">Molten Core to Zul'Aman</span><span class="chip" style="color:#4aa8ff;box-shadow:inset 0 0 0 2px #1a3a6a">1,446 items, searchable</span></div>
</div>
<img class="shot" src="data:image/png;base64,${b64(shotPath)}">
</div></body></html>`;

const br = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
fs.mkdirSync(path.join(root, 'docs'), { recursive: true });
for (const [file, size] of [['docs/logo.png', 512], ['docs/logo-1024.png', 1024]]) {
  const pg = await br.newPage({ viewport: { width: size, height: size } });
  await pg.setContent(`<!doctype html><html><body style="margin:0;background:transparent">${LOGO.replace('<svg ', `<svg width="${size}" height="${size}" `)}</body></html>`);
  await pg.screenshot({ path: path.join(root, file), omitBackground: true });
  await pg.close();
}
// the game reads uncompressed 32-bit TGA (bottom row first) with a power-of-two size
{
  const pg = await br.newPage({ viewport: { width: 128, height: 128 } });
  await pg.setContent('<!doctype html><html><body style="margin:0"><canvas id="c" width="64" height="64"></canvas></body></html>');
  const px = await pg.evaluate(async svg => {
    const img = new Image();
    img.src = 'data:image/svg+xml;base64,' + btoa(svg);
    await img.decode();
    const c = document.getElementById('c').getContext('2d');
    c.drawImage(img, 0, 0, 64, 64);
    return Array.from(c.getImageData(0, 0, 64, 64).data);
  }, LOGO.replace('<svg ', '<svg width="512" height="512" '));
  const head = Buffer.alloc(18);
  head[2] = 2;                                // uncompressed true colour
  head.writeUInt16LE(64, 12); head.writeUInt16LE(64, 14);
  head[16] = 32; head[17] = 8;                // 32 bits, 8 of them alpha, bottom-left origin
  const body = Buffer.alloc(64 * 64 * 4);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const s = ((63 - y) * 64 + x) * 4, d = (y * 64 + x) * 4;
    body[d] = px[s + 2]; body[d + 1] = px[s + 1]; body[d + 2] = px[s]; body[d + 3] = px[s + 3];
  }
  fs.mkdirSync(path.join(root, 'LootRuler/Media'), { recursive: true });
  fs.writeFileSync(path.join(root, 'LootRuler/Media/Logo.tga'), Buffer.concat([head, body]));
  await pg.close();
}
const pg = await br.newPage({ viewport: { width: 1280, height: 640 } });
await pg.setContent(banner());
await pg.waitForTimeout(300);
await pg.screenshot({ path: path.join(root, 'docs/banner.png') });
await br.close();
console.log('logo and banner written');
