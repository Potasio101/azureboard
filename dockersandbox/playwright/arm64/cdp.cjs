#!/usr/bin/env node
// Inspecciona por CDP el Chromium compartido que levanta debug-stack.sh.
// Uso:  node cdp.cjs <state|shot|console>
//   state    -> URL + título de cada pestaña
//   shot     -> screenshot de la pestaña activa a /tmp/current-view.png
//   console  -> mensajes de error de consola de la pestaña activa
//
// connectOverCDP(...).close() solo DESCONECTA; no cierra el navegador del humano.

// Auto-detecta playwright-core (el hash de _npx puede variar entre sandboxes)
const { execSync } = require('child_process');
let PW;
try {
  PW = execSync('find /home/agent/.npm -path "*playwright-core/index.js" 2>/dev/null | head -1')
    .toString().trim();
} catch (_) {}
if (!PW) { console.error('No encuentro playwright-core. ¿Corriste setup-playwright.sh?'); process.exit(1); }
const { chromium } = require(PW);

const CDP = 'http://127.0.0.1:9222';
const cmd = process.argv[2] || 'state';

(async () => {
  const b = await chromium.connectOverCDP(CDP);
  const ctx = b.contexts()[0];
  const pages = ctx.pages();
  const active = pages[pages.length - 1];

  if (cmd === 'state') {
    for (const pg of pages) console.log('•', (await pg.title()), '\n   ', (await pg.url()).slice(0, 120));
  } else if (cmd === 'shot') {
    await active.screenshot({ path: '/tmp/current-view.png' });
    console.log('screenshot -> /tmp/current-view.png  (', await active.url(), ')');
  } else if (cmd === 'console') {
    // Sólo captura mensajes NUEVOS durante una breve escucha; recarga si necesitas histórico
    const errs = [];
    active.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
    active.on('pageerror', e => errs.push('PAGEERROR: ' + e.message));
    await active.waitForTimeout(2500);
    console.log(errs.length ? errs.join('\n') : '(sin errores de consola en la ventana de escucha)');
  } else {
    console.error('Comando desconocido:', cmd);
  }
  await b.close();
})().catch(e => { console.error('FAIL', (e.message || e).split('\n')[0]); process.exit(1); });
