// Draws the screens tests/ui.lua captured (build/shots/*.json) as PNG pictures, so the addon's layout can be
// looked at without the game: node tools/render.mjs [build/shots]
// Item and spell icons come from Wowhead's icon server when it can be reached; the game's own interface art
// is drawn as close stand-ins (dialog borders, gold title plates, red buttons, slot frames).
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';

let chromium;
try { ({ chromium } = await import('playwright')); } catch { ({ chromium } = await import('/opt/node-tools/node_modules/playwright/index.mjs')); }

const dir = path.resolve(process.argv[2] || 'build/shots');
const files = fs.readdirSync(dir).filter(f => f.endsWith('.json')).sort();

const rgba = (c, a = 1) => c ? `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${(c[3] ?? 1) * a})` : 'transparent';
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function richText(t, base) {
  // |cffRRGGBB ... |r colour codes and |T...|t inline textures
  let out = '', i = 0, open = 0;
  while (i < t.length) {
    if (t.startsWith('|c', i) && /^[0-9a-fA-F]{8}$/.test(t.slice(i + 2, i + 10))) { out += `<span style="color:#${t.slice(i + 4, i + 10)}">`; open++; i += 10; continue; }
    if (t.startsWith('|r', i)) { if (open) { out += '</span>'; open--; } i += 2; continue; }
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
    if (/Background-Dark/i.test(op.bg || '')) bg = `rgba(${Math.round(16 * tint[0])},${Math.round(13 * tint[1])},${Math.round(10 * tint[2])},${tint[3] ?? 1})`;
    else if (/Background/i.test(op.bg || '')) bg = `rgba(${Math.round(30 * tint[0])},${Math.round(26 * tint[1])},${Math.round(22 * tint[2])},${tint[3] ?? 1})`;
    else if (/WHITE8X8/i.test(op.bg || '')) bg = rgba(op.color || [0, 0, 0, 0]);
    else if (/SliderBar-Background/i.test(op.bg || '')) bg = '#0b0907';
    const bc = op.border || [1, 1, 1, 1];
    if (/DialogBox-Border/i.test(op.edge || '')) { border = '3px solid #8a7550'; shadow = 'box-shadow: inset 0 0 0 2px #2a2216, 0 0 0 1px #000;'; radius = 8; }
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
  if (op.kind === 'edit') {
    return `<div style="${base}box-sizing:border-box;border:1px solid #6b5530;background:#050403;border-radius:3px;color:#fff;font:12px 'Friz Quadrata','Segoe UI',Arial;line-height:${b.h}px;padding-left:6px;overflow:hidden;white-space:nowrap">${esc(op.text || '')}</div>`;
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
  const win = shot.ops.find(o => o.kind === 'backdrop' && o.name === 'TBCrushCalcFrame');
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
