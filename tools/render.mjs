// Draws the screens tests/ui.lua captured (build/shots/*.json) as PNG pictures, so the addon's layout can be
// looked at without the game: node tools/render.mjs [build/shots]
// Item icons come from Wowhead's icon server when it can be reached (ICONS=1); the game's own interface art
// is drawn as close stand-ins (dialog borders, gold title plates, red buttons).
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';

let chromium;
try { ({ chromium } = await import('playwright')); } catch { ({ chromium } = await import('/opt/node-tools/node_modules/playwright/index.mjs')); }

const dir = path.resolve(process.argv[2] || 'build/shots');
const logoFile = path.join(path.dirname(path.dirname(new URL(import.meta.url).pathname)), 'docs/logo.png');
const LOGO = fs.existsSync(logoFile) ? `data:image/png;base64,${fs.readFileSync(logoFile).toString('base64')}` : null;
const files = fs.readdirSync(dir).filter(f => f.endsWith('.json')).sort();

const rgba = (c, a = 1) => c ? `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${(c[3] ?? 1) * a})` : 'transparent';
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function richText(t, base) {
  // |cffRRGGBB ... |r colour codes, |T...|t inline textures and |H...|h links
  let out = '', i = 0, open = 0;
  while (i < t.length) {
    if (t.startsWith('|c', i) && /^[0-9a-fA-F]{8}$/.test(t.slice(i + 2, i + 10))) { out += `<span style="color:#${t.slice(i + 4, i + 10)}">`; open++; i += 10; continue; }
    if (t.startsWith('|r', i)) { if (open) { out += '</span>'; open--; } i += 2; continue; }
    // |Hitem:...|h[Name]|h hyperlinks: the game shows just the name
    if (t.startsWith('|H', i)) { const end = t.indexOf('|h', i); if (end > 0) { i = end + 2; continue; } }
    if (t.startsWith('|h', i)) { i += 2; continue; }
    if (t.startsWith('|T', i)) {
      const end = t.indexOf('|t', i);
      const parts = t.slice(i + 2, end).split(':');
      const col = parts.length >= 14 ? `rgb(${parts[11]},${parts[12]},${parts[13]})` : '#888';
      out += `<span style="display:inline-block;width:9px;height:9px;background:${col};vertical-align:-1px"></span>`;
      i = end + 2; continue;
    }
    if (t[i] === '\n') { out += '<br>'; i++; continue; }
    out += esc(t[i]); i++;
  }
  while (open--) out += '</span>';
  return out;
}

function iconName(tex) {
  const m = /^Interface\\Icons\\(.+)$/i.exec(tex || '');
  return m ? m[1].toLowerCase() : null;
}

function clipStyle(op) {
  if (!op.clip) return '';
  const c = op.clip, b = op.box;
  const top = Math.max(0, c.y - b.y), left = Math.max(0, c.x - b.x);
  const bottom = Math.max(0, (b.y + b.h) - (c.y + c.h)), right = Math.max(0, (b.x + b.w) - (c.x + c.w));
  if (top >= b.h || left >= b.w || bottom >= b.h || right >= b.w) return 'display:none;';
  return `clip-path: inset(${top}px ${right}px ${bottom}px ${left}px);`;
}

function opHtml(op) {
  const b = op.box;
  if (b.w <= 0 || b.h <= 0) return '';
  if (clipStyle(op).startsWith('display:none')) return '';
  const base = `position:absolute;left:${b.x}px;top:${b.y}px;width:${b.w}px;height:${b.h}px;opacity:${op.alpha ?? 1};${clipStyle(op)}`;
  if (op.kind === 'backdrop') {
    let bg = 'transparent', border = 'none', radius = 4, shadow = '';
    const tint = op.color || [1, 1, 1, 1];
    if (/Gold-Background/i.test(op.bg || '')) bg = `rgba(${Math.round(24 * tint[0])},${Math.round(18 * tint[1])},${Math.round(8 * tint[2])},${tint[3] ?? 1})`;
    else if (/Background-Dark/i.test(op.bg || '')) bg = `rgba(${Math.round(16 * tint[0])},${Math.round(13 * tint[1])},${Math.round(10 * tint[2])},${tint[3] ?? 1})`;
    else if (/Background/i.test(op.bg || '')) bg = `rgba(${Math.round(30 * tint[0])},${Math.round(26 * tint[1])},${Math.round(22 * tint[2])},${tint[3] ?? 1})`;
    else if (/WHITE8X8/i.test(op.bg || '')) bg = rgba(op.color || [0, 0, 0, 0]);
    else if (/SliderBar-Background/i.test(op.bg || '')) bg = '#0b0907';
    const bc = op.border || [1, 1, 1, 1];
    if (/Gold-Border/i.test(op.edge || '')) { border = '3px solid #c9a227'; shadow = 'box-shadow: inset 0 0 0 2px #3a2a0a, 0 0 0 1px #000;'; radius = 8; }
    else if (/DialogBox-Border/i.test(op.edge || '')) { border = '3px solid #8a7550'; shadow = 'box-shadow: inset 0 0 0 2px #2a2216, 0 0 0 1px #000;'; radius = 8; }
    else if (/Tooltip-Border/i.test(op.edge || '')) { border = `${op.edgeSize >= 16 ? 2 : 1}px solid ${rgba(bc)}`; radius = op.edgeSize >= 16 ? 5 : 4; }
    else if (/WHITE8X8/i.test(op.edge || '')) { border = `${op.edgeSize || 1}px solid ${rgba(bc)}`; radius = 2; }
    else if (/SliderBar-Border/i.test(op.edge || '')) { border = '1px solid #6b5530'; radius = 6; }
    return `<div style="${base}background:${bg};border:${border};border-radius:${radius}px;box-sizing:border-box;${shadow}"></div>`;
  }
  if (op.kind === 'panelbutton') {
    return `<div style="${base}border-radius:4px;box-sizing:border-box;border:1px solid #000;background:${op.enabled ? 'linear-gradient(#a31a12,#6a0c07 55%,#4a0703)' : 'linear-gradient(#555,#333)'};box-shadow:inset 0 1px 0 rgba(255,200,150,.35),0 0 0 1px #b5893a"></div>`;
  }
  if (op.kind === 'closebutton') {
    return `<div style="${base}"><div style="position:absolute;left:6px;top:6px;width:20px;height:20px;border-radius:50%;background:radial-gradient(circle at 40% 35%,#c2321e,#5e0a03);border:1px solid #b5893a;color:#ffd9b0;font:bold 12px Arial;text-align:center;line-height:20px">x</div></div>`;
  }
  if (op.kind === 'edit' && op.multi) {
    return `<div style="${base}color:#fff;font:11px/13px 'Friz Quadrata','Segoe UI',Arial;white-space:pre;overflow:hidden;background:rgba(80,120,200,.25)">${esc(op.text || '')}</div>`;
  }
  if (op.kind === 'edit') {
    return `<div style="${base}box-sizing:border-box;border:1px solid #6b5530;background:#050403;border-radius:3px;color:#fff;font:12px 'Friz Quadrata','Segoe UI',Arial;line-height:${b.h}px;padding-left:6px;overflow:hidden;white-space:nowrap">${richText((op.text || '').replace(/\|H.-\|h(.-)\|h/g, '$1').replace(/\|H[^|]*\|h(.*?)\|h/g, '$1'), [1, 1, 1])}</div>`;
  }
  if (op.kind === 'texture') {
    const tint = op.vertex || [1, 1, 1, 1];
    if (op.color) return `<div style="${base}background:${rgba([op.color[0] * tint[0], op.color[1] * tint[1], op.color[2] * tint[2], (op.color[3] ?? 1) * (tint[3] ?? 1)])}"></div>`;
    const tex = op.tex || '';
    const ic = iconName(tex);
    const desat = op.desat ? 'filter:grayscale(1) brightness(.6);' : '';
    if (ic) {
      const letters = ic.replace(/^(inv|spell|ability|achievement|trade)_/, '').slice(0, 2).toUpperCase();
      return `<div style="${base}${desat}background:radial-gradient(#3a2d1d,#120d08);color:#c9a227;font:bold ${Math.max(8, b.h * 0.35)}px Georgia;display:flex;align-items:center;justify-content:center;overflow:hidden">${letters}<img src="https://wow.zamimg.com/images/wow/icons/large/${ic}.jpg" onerror="this.remove()" style="position:absolute;left:-7%;top:-7%;width:114%;height:114%"></div>`;
    }
    if (/UI-CheckBox-Up/i.test(tex)) return `<div style="${base}"><div style="position:absolute;inset:18%;background:linear-gradient(#1a1712,#0a0907);border:1px solid #8a7a5a;border-radius:2px;box-shadow:inset 0 0 2px #000"></div></div>`;
    if (/UI-CheckBox-Check/i.test(tex)) return `<div style="${base}color:#ffd100;font:bold ${Math.round(b.h * 0.75)}px Arial;display:flex;align-items:center;justify-content:center;text-shadow:0 0 2px #000">&#10004;</div>`;
    if (/UI-CheckBox-Highlight/i.test(tex)) return '';
    if (/DialogBox-Header/i.test(tex) && op.coord) {
      // a piece of the plate (Kit's three-piece title plate): its left end, the middle, or its right end
      const u = op.coord[0];
      const piece = u < 0.3 ? 'left:45%;right:0;border-right:0;border-radius:5px 0 0 5px'
        : u > 0.6 ? 'left:0;right:45%;border-left:0;border-radius:0 5px 5px 0' : 'left:0;right:0;border-left:0;border-right:0';
      return `<div style="${base}"><div style="position:absolute;border:2px solid #c9a227;${piece};top:35%;bottom:6%;background:linear-gradient(#3b2a12,#1c1209);box-shadow:0 1px 0 0 #000"></div></div>`;
    }
    if (/DialogBox-Header/i.test(tex)) return `<div style="${base}"><div style="position:absolute;left:18%;right:18%;top:22%;bottom:30%;background:linear-gradient(#3b2a12,#1c1209);border:2px solid #c9a227;border-radius:5px;box-shadow:0 0 0 1px #000"></div></div>`;
    if (/ActionButton-Border/i.test(tex)) return `<div style="${base}"><div style="position:absolute;inset:27%;border-radius:5px;box-shadow:0 0 7px 2px ${rgba(tint, 0.9)}"></div></div>`;
    if (/UI-PaperDoll-Slot/i.test(tex)) { const n = tex.split('-').pop(); return `<div style="${base}${op.alpha < 1 ? '' : ''}background:radial-gradient(#2a241c,#0c0a08);color:#6d6253;font:bold 7px Arial;display:flex;align-items:center;justify-content:center;text-transform:uppercase">${esc(n)}</div>`; }
    if (/CharacterCreate-Classes/i.test(tex)) return `<div style="${base}border-radius:50%;background:radial-gradient(#5a4a2a,#1a1208);border:1px solid #c9a227;box-sizing:border-box;color:#ffd100;font:bold ${b.h * 0.45}px Georgia;display:flex;align-items:center;justify-content:center">C</div>`;
    if (/TalentFrame\\/i.test(tex) && !/Arrows/i.test(tex)) return `<div style="${base}background:linear-gradient(160deg,#2b3a52,#1a1410);"></div>`;
    if (/TalentArrows/i.test(tex)) return `<div style="${base}"><div style="position:absolute;left:30%;top:30%;width:0;height:0;border-left:5px solid transparent;border-right:5px solid transparent;border-top:8px solid ${op.coord && op.coord[2] >= 0.5 ? '#777' : '#ffd100'}"></div></div>`;
    if (/EmptySocket/i.test(tex)) return `<div style="${base}border-radius:50%;background:#222;border:2px solid #555;box-sizing:border-box"></div>`;
    if (/GroupLoot-Pass/i.test(tex)) return `<div style="${base}color:#c9a227;font:bold 14px Arial;display:flex;align-items:center;justify-content:center">x</div>`;
    if (/Backpack-EmptySlot/i.test(tex)) return `<div style="${base}background:#151210;border:1px solid #333;box-sizing:border-box"></div>`;
    if (/SliderBar-Button/i.test(tex)) return '';
    if (/Minimap/i.test(tex)) return '';
    if (/LootRuler\\Media\\Logo/i.test(tex) && LOGO) {
      const c = op.coord || [0, 1, 0, 1];
      const w = b.w / (c[1] - c[0]), h = b.h / (c[3] - c[2]);
      return `<div style="${base}overflow:hidden"><img src="${LOGO}" style="position:absolute;left:${-c[0] * w}px;top:${-c[2] * h}px;width:${w}px;height:${h}px"></div>`;
    }
    // the group loot frame's art
    if (/UI-EmptySlot/i.test(tex)) return `<div style="${base}"><div style="position:absolute;inset:22%;background:#100d0a;border:1px solid #5a4a30;box-shadow:inset 0 0 6px #000"></div></div>`;
    if (/Merchant-LabelSlots/i.test(tex)) return `<div style="${base}"><div style="position:absolute;left:2%;right:22%;top:10%;bottom:46%;background:rgba(0,0,0,.45);border:1px solid #6b5530;border-radius:3px"></div></div>`;
    if (/Gold-Dragon|DialogBox-Corner|DialogBox-Gold-Corner/i.test(tex)) return '';
    if (/GroupLoot-Dice-Up/i.test(tex)) return `<div style="${base}${desat}"><div style="position:absolute;inset:16%;background:linear-gradient(135deg,${rgba([tint[0], tint[1], tint[2], 1])},${rgba([0.81 * tint[0], 0.78 * tint[1], 0.71 * tint[2], 1])});border-radius:5px;border:1px solid #4a3a20;box-shadow:1px 1px 0 #000"><i style="position:absolute;left:22%;top:22%;width:4px;height:4px;border-radius:50%;background:#7a1010"></i><i style="position:absolute;left:44%;top:44%;width:4px;height:4px;border-radius:50%;background:#7a1010"></i><i style="position:absolute;right:22%;bottom:22%;width:4px;height:4px;border-radius:50%;background:#7a1010"></i></div></div>`;
    if (/GroupLoot-Coin-Up/i.test(tex)) return `<div style="${base}${desat}"><div style="position:absolute;inset:16%;border-radius:50%;background:radial-gradient(circle at 35% 35%,#ffe9a0,#c9922a 60%,#7a5410);border:1px solid #4a3410;box-shadow:1px 1px 0 #000"></div></div>`;
    if (/GroupLoot-(Dice|Coin)-(Down|Highlight)/i.test(tex)) return '';
    if (/Skills-BarBorder/i.test(tex)) return `<div style="${base}"><div style="position:absolute;left:0;right:0;top:25%;bottom:25%;border:1px solid #9a8560;border-radius:2px;box-shadow:0 0 0 1px #000"></div></div>`;
    if (/Skills-Bar/i.test(tex)) return `<div style="${base}background:linear-gradient(${rgba(tint)},${rgba([tint[0] * 0.6, tint[1] * 0.6, tint[2] * 0.6, tint[3] ?? 1])})"></div>`;
    if (/Indicator-Yellow/i.test(tex)) return `<div style="${base}border-radius:50%;background:radial-gradient(#ffe066,#c98a00)"></div>`;
    if (/ButtonHilight|QuestTitleHighlight/i.test(tex)) return '';
    return `<div style="${base}background:repeating-linear-gradient(45deg,#3a0040,#3a0040 4px,#200020 4px,#200020 8px)" title="${esc(tex)}"></div>`;
  }
  if (op.kind === 'model') {
    return `<div style="${base}display:flex;align-items:center;justify-content:center"><svg viewBox="0 0 60 120" style="height:92%"><circle cx="30" cy="14" r="10" fill="#6a5a7a"/><path d="M14 30h32l6 40h-8l-2 46h-10l-2-36-2 36h-10l-2-46h-8z" fill="#6a5a7a"/></svg><div style="position:absolute;bottom:2px;width:100%;text-align:center;color:#9d9d9d;font:10px Georgia">3D model (${op.worn} items)</div></div>`;
  }
  if (op.kind === 'atlas') {
    return `<div style="${base}border-radius:50%;background:radial-gradient(#6a5a3a,#2a1a08);border:2px solid #c9a227;box-sizing:border-box;color:#ffd100;font:bold ${b.h * 0.25}px Georgia;display:flex;align-items:center;justify-content:center;text-transform:capitalize">${esc((op.atlas || '').split('-')[1] || '')}</div>`;
  }
  if (op.kind === 'text') {
    const c = op.color || [1, 1, 1];
    const just = { LEFT: 'left', CENTER: 'center', RIGHT: 'right' }[op.justifyH] || 'center';
    const valign = { TOP: 'flex-start', MIDDLE: 'center', BOTTOM: 'flex-end' }[op.justifyV] || 'center';
    const lines = op.maxLines ? `display:-webkit-box;-webkit-line-clamp:${op.maxLines};-webkit-box-orient:vertical;overflow:hidden;` : '';
    return `<div style="${base}display:flex;align-items:${valign};justify-content:${just === 'left' ? 'flex-start' : just === 'right' ? 'flex-end' : 'center'};overflow:visible">
      <div style="width:100%;text-align:${just};color:${rgba(c)};font:${op.size}px/${Math.round(op.size * 1.18)}px 'Friz Quadrata','Palatino Linotype','Book Antiqua',Georgia,serif;text-shadow:1px 1px 0 #000;${op.wrap ? '' : 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;'}${lines}">${richText(op.text, c)}</div></div>`;
  }
  return '';
}

const b = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
const page = await b.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1.5 });
await page.route(/zamimg/, r => (process.env.ICONS ? r.continue() : r.abort()));
for (const f of files) {
  const shot = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
  // the picture is cut to the window, or to the frames the test named (shot.focus)
  let win = shot.ops.find(o => o.kind === 'backdrop' && o.name === 'LootRulerFrame');
  if (shot.focus) {
    const boxes = shot.ops.filter(o => o.kind === 'backdrop' && shot.focus.includes(o.name)).map(o => o.box);
    if (boxes.length) {
      const x = Math.min(...boxes.map(b => b.x)), y = Math.min(...boxes.map(b => b.y));
      const r = Math.max(...boxes.map(b => b.x + b.w)), btm = Math.max(...boxes.map(b => b.y + b.h));
      win = { box: { x: x - 6, y: y - 6, w: r - x + 12, h: btm - y + 12 } };
    }
  }
  const html = `<!doctype html><html><body style="margin:0;background:#2a3540;width:${shot.w}px;height:${shot.h}px;position:relative;overflow:hidden">${shot.ops.map(opHtml).join('\n')}</body></html>`;
  await page.setContent(html);
  await page.waitForTimeout(process.env.ICONS ? 800 : 50);
  const out = path.join(dir, f.replace(/\.json$/, '.png'));
  const clip = win ? { x: Math.max(0, win.box.x - 6), y: Math.max(0, win.box.y - 6), width: win.box.w + 12, height: win.box.h + 12 } : undefined;
  await page.screenshot({ path: out, clip });
}
await b.close();
console.log(`drew ${files.length} screens into ${dir}`);
void http;
