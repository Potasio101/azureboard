#!/usr/bin/env node
// Vigía: sondea el Chromium compartido por CDP y termina (notificando) en cuanto la
// pestaña activa deja de estar en login.* y vuelve al dominio de la app.
// Lánzalo con run_in_background: true para que la IA sea notificada al completarse.
//
// Edita APP si cambias de aplicación.

const APP = 'carepathmigration-e8hvgngegxc8cwfx.centralus-01.azurewebsites.net';

const { execSync } = require('child_process');
const PW = execSync('find /home/agent/.npm -path "*playwright-core/index.js" 2>/dev/null | head -1').toString().trim();
const { chromium } = require(PW);
const CDP = 'http://127.0.0.1:9222';

(async () => {
  for (let i = 0; i < 240; i++) {           // hasta ~20 min (240 * 5s)
    try {
      const b = await chromium.connectOverCDP(CDP);
      const pages = b.contexts()[0].pages();
      let onApp = null;
      for (const pg of pages) {
        const u = await pg.url();
        if (u.includes(APP) && !u.includes('login')) onApp = u;
      }
      await b.close();
      if (onApp) { console.log('AUTHENTICATED ->', onApp); process.exit(0); }
    } catch (_) { /* el navegador aún no responde; reintenta */ }
    await new Promise(r => setTimeout(r, 5000));
  }
  console.log('TIMEOUT: sigue sin autenticar tras ~20 min');
})();
