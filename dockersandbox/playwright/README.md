# Playwright MCP + VNC en Docker Sandbox

Guía **lista para cualquier IA** para dejar operativo el MCP de Playwright en este
Docker Sandbox y, opcionalmente, compartir el navegador con el humano por VNC para
que él haga login (Entra ID/MFA/etc.) mientras la IA sigue inspeccionando la misma
sesión por CDP.

> **Objetivo:** que un agente futuro NO gaste tokens en *discovery*. Aquí está todo
> lo que se descubrió a base de prueba y error. Sigue los pasos tal cual.

---

## 0. ¿Qué arquitectura tienes?

```bash
uname -m
```

- `aarch64` / `arm64` → **usa la carpeta [`arm64/`](./arm64/)** (este entorno, probado y funcionando).
- `x86_64` → carpeta `x86_64/` (pendiente; ver notas al final). Probablemente el setup
  sea más simple porque Google Chrome **sí** tiene build x86_64, pero replica la misma estructura.

Este documento describe el caso **ARM64**, que es el que está validado.

---

## 1. El problema raíz en ARM64 (lee esto primero)

El MCP de Playwright (`@playwright/mcp@latest`) arranca por defecto con `--browser chrome`,
es decir el **Google Chrome de marca**, que busca en `/opt/google/chrome/chrome`.

**Google Chrome NO se distribuye para Linux ARM64.** `npx playwright install chrome` falla con:

```
ERROR: not supported on Linux Arm64
```

→ Solución: instalar el **Chromium empaquetado** de Playwright (sí existe para ARM64) y
hacer que el MCP lo encuentre en la ruta que espera. Ver `arm64/setup-playwright.sh`.

---

## 2. Setup del MCP (modo headless — recomendado para uso normal)

Ejecuta una sola vez por sandbox:

```bash
bash dockersandbox/playwright/arm64/setup-playwright.sh
```

Qué hace (y por qué), resumido:

1. **`npx playwright install chromium`** — instala el Chromium ARM64 en
   `~/.cache/ms-playwright/chromium-<rev>/chrome-linux/chrome`.
2. **Symlink** ese binario a `/opt/google/chrome/chrome` (la ruta que el MCP espera).
   - Esto evita tener que editar la config del MCP. La config vive en
     `~/.claude.json` bajo `projects.<ruta>.mcpServers.playwright` y es **read-only**
     (gestionada por el harness): cambiar `args` a `--browser chromium` exigiría
     **recrear el sandbox**. El symlink lo resuelve sin tocar nada.
3. **`sudo npx playwright install-deps chromium`** — instala ~20 libs del sistema
   (libX11, libgbm, libnss3, libasound2, cairo, pango, etc.). Sin ellas Chromium ni arranca.
   - ⚠️ **Si `apt` falla** con `Unable to parse package file ... InRelease (1)` o errores
     de verificación de firma OpenPGP, las listas de apt están corruptas. Arréglalo con:
     ```bash
     sudo rm -rf /var/lib/apt/lists/* && sudo apt-get update
     ```
     y reintenta `install-deps`.

Verificación de que quedó bien:

```bash
ldd /opt/google/chrome/chrome 2>/dev/null | grep -c "not found"   # debe dar 0
/opt/google/chrome/chrome --version                                # Chromium 1XX...
```

Tras esto, las tools `mcp__playwright__browser_*` funcionan directamente (headless de facto).
Prueba mínima: `browser_navigate` a una URL + `browser_snapshot`.

### Headless vs headed (probado)

| Modo | ¿Funciona? | Cómo |
|------|-----------|------|
| **Headless** | ✅ | Directo, sin display. Es lo recomendado. |
| **Headed sin display** | ❌ | Falla: no hay pantalla en el sandbox. |
| **Headed con Xvfb** | ✅ | Necesita un display virtual. Es la base del modo VNC (sección 3). |

---

## 3. Modo VNC compartido (humano hace login, IA sigue depurando)

Caso de uso: la app exige autenticación (p.ej. **Entra ID / Azure AD con MFA**) y el
agente no puede/ debe teclear credenciales. El humano abre el navegador por VNC, hace
login, y la IA inspecciona **el mismo navegador** por el puerto de depuración (CDP).

```
        HUMANO (host)                         IA (sandbox)
  navegador → 127.0.0.1:6080  ──VNC──►  Chromium headed en Xvfb :99
     (teclea login + MFA)                       │
                                          CDP 127.0.0.1:9222
                                          (consola, red, DOM, screenshots)
```

### 3.1 Levantar la pila (desde el sandbox)

**IMPORTANTE — backgrounding:** los procesos lanzados con `&` dentro de una sola llamada
Bash **se matan** al terminar el comando (el harness liquida el árbol de procesos).
Por eso la pila va en un **script supervisor que termina en `wait`** y se lanza con la
opción **`run_in_background: true`** de la tool Bash. NO intentes `setsid`/`nohup` sueltos:
también mueren.

```
# Lanzar con run_in_background: true
bash dockersandbox/playwright/arm64/debug-stack.sh
```

Edita la variable `URL` al principio de `debug-stack.sh` para apuntar a tu app.
El script arranca, en orden: `Xvfb :99` → Chromium headed (con `--remote-debugging-port=9222`
y perfil persistente en `/tmp/chrome-profile`) → `x11vnc` (puerto 5900, localhost) →
`websockify`/noVNC (web en `0.0.0.0:6080`).

Verifica que todo está arriba:

```bash
for p in "Xvfb :99" "remote-debugging-port=9222" x11vnc websockify; do
  pgrep -f "$p" >/dev/null && echo "$p: UP" || echo "$p: DOWN"; done
curl -s -o /dev/null -w "noVNC -> %{http_code}\n" http://127.0.0.1:6080/vnc.html   # 200
curl -s http://127.0.0.1:9222/json/version | head -c 80                            # CDP vivo
```

### 3.2 Publicar el puerto (el HUMANO, en su host)

```bash
sbx ports <SANDBOX_VM_ID> --publish 6080:6080/tcp
```

`<SANDBOX_VM_ID>` = valor de `echo $SANDBOX_VM_ID` dentro del sandbox (= `hostname`).
En este proyecto fue **`claude-azureboard`**.

### 3.3 Abrir noVNC (el HUMANO)

```
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote
```

> ⚠️ **USA `127.0.0.1`, NO `localhost`.** Verificado en este entorno: con `localhost`
> da "failed to load page"; con `127.0.0.1` funciona. Causa: `localhost` resuelve a IPv6
> `::1` y el `sbx ports` publica sobre IPv4 → no hay listener IPv6 que casar.

El humano verá el Chromium real y podrá teclear sus credenciales / completar MFA.
La IA **no** ve lo que teclea (solo controla por CDP).

### 3.4 La IA inspecciona por CDP

No uses las tools `mcp__playwright__*` para esto (el MCP arranca su propio Chromium
aparte). Conéctate al Chromium compartido con un script Node usando `connectOverCDP`:

```bash
node dockersandbox/playwright/arm64/cdp.cjs state     # URL + título de cada pestaña
node dockersandbox/playwright/arm64/cdp.cjs shot       # screenshot -> /tmp/current-view.png
node dockersandbox/playwright/arm64/cdp.cjs console    # errores de consola
```

Para esperar a que el humano cruce el login sin malgastar turnos, lanza el vigía
(con `run_in_background: true`): te notifica cuando la URL deja de ser `login.*` y vuelve
al dominio de la app.

```
node dockersandbox/playwright/arm64/login-watch.cjs    # edita APP dentro si cambias de app
```

`connectOverCDP(...).close()` **solo desconecta**, no cierra el navegador del humano. Seguro.

### 3.5 Apagar y limpiar (teardown)

Dos pasos: (A) apagar la pila en el sandbox, (B) cerrar el puerto en el host.

**(A) En el sandbox** — usa el script (NO pegues los `pkill` sueltos en la tool Bash:
si el patrón coincide con la cmdline del propio comando, `pkill -f` se manda SIGTERM a
sí mismo → exit 144; como archivo es seguro porque su cmdline es solo la ruta):

```bash
bash dockersandbox/playwright/arm64/kill-stack.sh
```

Verifica que quedó apagado **por puertos** (no por nombre de proceso, justo para no
auto-matarse): el script ya lo hace e imprime `CDP/noVNC/display → apagado`.

**(B) En el host** — el humano cierra el puerto publicado:

```bash
sbx ports <SANDBOX_VM_ID> --unpublish 6080:6080/tcp
# para ver qué hay publicado:  sbx ports <SANDBOX_VM_ID>
```

**¿Qué pasa con cookies / sesión / login al apagar?**
- El perfil del navegador vive en **`/tmp/chrome-profile`** y `kill-stack.sh` lo **borra**
  (`rm -rf`). Con eso **desaparecen todas las cookies, tokens y la sesión iniciada**: la
  próxima vez se arranca de cero y hay que volver a hacer login. Esto es lo deseable para
  una app **de producción** (no dejar sesión viva en el sandbox).
- Si en algún momento quisieras **conservar** la sesión entre reinicios, cambia el
  `--user-data-dir` a una ruta persistente (p.ej. `~/.cache/carepath-profile`) y **no** la
  borres en el teardown. ⚠️ No recomendado con apps de producción / credenciales reales.
- Cerrar/abrir el **puerto** (`sbx ports`) NO afecta a las cookies: el puerto es solo el
  túnel de red; las cookies dependen del perfil del navegador, no del puerto.

**Seguridad:** el VNC va **sin contraseña** pero solo es accesible por el túnel de
`sbx ports` (escucha en la red del sandbox, no en Internet). Aun así, ciérralo al
terminar. Si quieres endurecerlo, añade `-rfbauth` a `x11vnc`.

---

## 4. Datos concretos de ESTE entorno (referencia rápida, evita re-discovery)

| Dato | Valor |
|------|-------|
| Arquitectura | `aarch64` (ARM64) |
| `SANDBOX_VM_ID` / hostname | `claude-azureboard` |
| Navegador | Chromium empaquetado de Playwright (no Google Chrome) |
| Binario Chromium | `~/.cache/ms-playwright/chromium-1223/chrome-linux/chrome` (la rev `1223` puede variar) |
| Symlink esperado por MCP | `/opt/google/chrome/chrome` → binario de arriba |
| Versión Chromium | 148.0.7778.0 |
| `playwright-core` (para scripts CDP) | `/home/agent/.npm/_npx/<hash>/node_modules/playwright-core` — **CommonJS, usa `require()`** (el `<hash>` puede cambiar; los scripts lo auto-detectan) |
| Config MCP | `~/.claude.json` → `projects["/Volumes/orico 1/projecto/azureboard"].mcpServers.playwright` — **READ-ONLY** |
| Display virtual | `:99` (Xvfb 1366x900x24) |
| Puerto CDP | `127.0.0.1:9222` |
| Puerto VNC | `5900` (localhost) |
| Puerto noVNC web | `0.0.0.0:6080` → publicar con `sbx ports` |
| eth0 | `172.17.0.1/31` — **NO** atar servicios a esta IP literal; usar `0.0.0.0` |

### Errores ya vistos y su causa (no repitas el discovery)

- **`Chromium distribution 'chrome' is not found at /opt/google/chrome/chrome`**
  → falta el symlink (sección 2, paso 2).
- **`not supported on Linux Arm64`** al instalar `chrome` → usa `chromium`, no `chrome`.
- **`Missing system dependencies required to run browser`** → `install-deps chromium`.
- **`Unable to parse package file ... InRelease (1)`** → listas apt corruptas:
  `sudo rm -rf /var/lib/apt/lists/* && sudo apt-get update`.
- **noVNC "failed to load page" con `localhost`** → usa `127.0.0.1` (IPv6 vs IPv4).
- **Servicio inalcanzable desde el host pese a estar UP** → estaba atado a `172.17.0.1`
  (eth0, una /31 que ni siquiera es loopback-alcanzable desde dentro). Ata a `0.0.0.0`.
- **Procesos de fondo que "desaparecen" (exit 144)** → `&`/`setsid` sueltos se matan;
  usa el script supervisor con `wait` + `run_in_background: true`.
- **`pkill -f "<patrón>"` devuelve exit 144 y se mata solo** → el patrón (p.ej. `x11vnc`,
  `websockify`, `remote-debugging-port=9222`) coincide con la **propia cmdline del comando**
  → se manda SIGTERM a sí mismo. NO uses `pkill -f` con esos literales desde la tool Bash.
  En su lugar relanza `debug-stack.sh` (su `pkill` interno es seguro: su cmdline es solo la
  ruta del script y no coincide con los patrones).
- **Chrome crashea / tabs "Aw snap" / "no puedo ni abrir google" / CDP `ECONNREFUSED`** →
  `/dev/shm` es de solo **64 MB** en el contenedor. Chrome necesita
  **`--disable-dev-shm-usage`** (usa `/tmp`), **`--no-sandbox`** y `--disable-gpu`.
  Ya están en `debug-stack.sh`. Verifícalo: `df -h /dev/shm`.
- **AADSTS900561: "endpoint only accepts POST requests. Received a GET request"** durante
  login Entra ID → el flujo `response_mode=form_post` se rompió, típicamente porque se usó
  **passkey/FIDO** y el Chromium del sandbox **no tiene authenticator** (ni security key ni
  platform passkey). Inicia sesión con **password + MFA por app/teléfono**, evita passkey.

---

## 4bis. Estado: VALIDADO end-to-end (2026-05-31)

Flujo completo probado y funcionando en `claude-azureboard` (ARM64):

1. Setup MCP (Chromium + symlink + deps) → ✅ headless OK.
2. Pila VNC levantada → humano abrió noVNC en `http://127.0.0.1:6080` → ✅.
3. Login Entra ID con **password + MFA** (NO passkey) → ✅ autenticado.
4. App cargó: **Carepath Migration Studio** (secciones Companies / Touchpoints /
   Occupants / Run Migration / Run History / Cache Manager).
5. IA inspecciona la sesión autenticada por CDP (`cdp.cjs state|shot|console`) → ✅.

Notas operativas aprendidas en vivo:
- **NO lances `login-watch.cjs` mientras la IA también consulta CDP**: el polling cada 5s
  compite por conexiones CDP y provoca timeouts (`connectOverCDP: Timeout`). Usa el vigía
  *o* consultas manuales, no ambos a la vez. Mejor: que el humano avise "ya entré".
- Tras un crash de Chrome, **relanza `debug-stack.sh`** (limpia e instala flags correctos);
  no intentes matar procesos a mano con `pkill -f`.

## 5. Pendiente: x86_64

Cuando toque, crear `x86_64/` con los mismos scripts. Diferencias esperadas:

- Google Chrome **sí** está disponible para x86_64, así que `npx playwright install chrome`
  debería funcionar y quizá **no haga falta el symlink** (el MCP encontraría Chrome solo).
  Aun así, usar Chromium empaquetado + symlink también funciona y es más portable.
- `install-deps`, el stack VNC (Xvfb/x11vnc/websockify), el truco de `127.0.0.1` vs
  `localhost`, el bind a `0.0.0.0` y la regla de background con `run_in_background`
  **son idénticos** — no dependen de la arquitectura.
- Validar y actualizar la tabla de la sección 4 con los valores de x86_64.
