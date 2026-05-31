#!/usr/bin/env node
// Barrido de debug sobre la sesión autenticada (vía CDP al navegador compartido).
// Recorre las secciones, captura errores de consola, requests fallidos (>=400 / failed)
// y un screenshot por sección. Salida JSON + PNGs en /tmp/sweep/.
const { execSync } = require('child_process');
const PW = execSync('find /home/agent/.npm -path "*playwright-core/index.js" 2>/dev/null | head -1').toString().trim();
const { chromium } = require(PW);
const fs = require('fs');

const SECTIONS = ['Companies', 'Touchpoints', 'Occupants', 'Run Migration', 'Run History', 'Cache Manager'];
const OUT = '/tmp/sweep';

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const b = await chromium.connectOverCDP('http://127.0.0.1:9222');
  const pg = b.contexts()[0].pages().slice(-1)[0];

  const report = {};
  let cur = { console: [], net: [], pageerr: [] };
  pg.on('console', m => { if (m.type() === 'error') cur.console.push(m.text().slice(0, 300)); });
  pg.on('pageerror', e => cur.pageerr.push((e.message || '').slice(0, 300)));
  pg.on('requestfailed', r => cur.net.push(`FAIL ${r.method()} ${r.url().slice(0,120)} :: ${r.failure()?.errorText||''}`));
  pg.on('response', async r => { const s = r.status(); if (s >= 400) cur.net.push(`${s} ${r.request().method()} ${r.url().slice(0,120)}`); });

  for (const name of SECTIONS) {
    cur = { console: [], net: [], pageerr: [] };
    let clicked = false;
    try {
      const link = pg.getByRole('link', { name }).or(pg.getByText(name, { exact: true })).first();
      await link.click({ timeout: 8000 });
      clicked = true;
    } catch (e) { cur.console.push(`[sweep] no pude click '${name}': ${(e.message||'').split('\n')[0]}`); }
    await pg.waitForTimeout(3500);
    const url = await pg.url();
    const file = `${OUT}/${name.replace(/\s+/g,'_')}.png`;
    try { await pg.screenshot({ path: file }); } catch (_) {}
    report[name] = { clicked, url, errors: cur.console, pageErrors: cur.pageerr, network: [...new Set(cur.net)] };
    console.log(`\n=== ${name} === (${clicked?'ok':'NO-CLICK'})  ${url}`);
    if (cur.pageerr.length) console.log('  pageerror:', cur.pageerr.join(' | '));
    if (cur.console.length) console.log('  console :', cur.console.join(' | '));
    const net = [...new Set(cur.net)];
    if (net.length) console.log('  network :', net.join('\n            '));
    if (!cur.pageerr.length && !cur.console.length && !net.length) console.log('  (sin errores)');
  }

  fs.writeFileSync(`${OUT}/report.json`, JSON.stringify(report, null, 2));
  console.log(`\nReporte: ${OUT}/report.json  ·  screenshots en ${OUT}/`);
  await b.close();
})().catch(e => { console.error('FAIL', (e.message || e).split('\n')[0]); process.exit(1); });
