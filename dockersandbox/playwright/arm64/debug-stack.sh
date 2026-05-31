#!/bin/bash
# Pila de depuración con navegador compartido por VNC (ARM64).
# Xvfb :99 -> Chromium(headed + CDP 9222) -> x11vnc(5900) -> noVNC web(0.0.0.0:6080)
#
# LANZAR SIEMPRE con la opción run_in_background: true de la tool Bash.
# (Los procesos en background sueltos se matan al terminar el comando; este script
#  termina en `wait` para mantener vivo todo el árbol.)
#
# Tras lanzarlo, el HUMANO publica el puerto desde su host:
#     sbx ports <SANDBOX_VM_ID> --publish 6080:6080/tcp
# y abre (¡con 127.0.0.1, NO localhost!):
#     http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote
set -m

# >>> EDITA ESTA URL para tu app <<<
URL="https://carepathmigration-e8hvgngegxc8cwfx.centralus-01.azurewebsites.net/"

export DISPLAY=:99
CHROME=/opt/google/chrome/chrome

# Limpieza de instancias previas
pkill -f "Xvfb :99" 2>/dev/null
pkill -f "remote-debugging-port=9222" 2>/dev/null
pkill -f "x11vnc" 2>/dev/null
pkill -f "websockify" 2>/dev/null
sleep 1

# 1) Pantalla virtual
Xvfb :99 -screen 0 1366x900x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
sleep 2

# 2) Chromium headed con puerto de depuración (para que la IA inspeccione por CDP)
#    y perfil persistente (mantiene la sesión tras login del humano)
#    Flags críticos en contenedor: /dev/shm suele ser 64M -> tabs crashean ("Aw snap").
#    --disable-dev-shm-usage fuerza usar /tmp. --no-sandbox necesario sin userns.
"$CHROME" \
  --remote-debugging-port=9222 --remote-debugging-address=127.0.0.1 \
  --user-data-dir=/tmp/chrome-profile \
  --no-sandbox --disable-dev-shm-usage --disable-gpu \
  --no-first-run --no-default-browser-check \
  --window-position=0,0 --window-size=1366,900 \
  "$URL" >/tmp/chrome.log 2>&1 &
sleep 4

# 3) VNC del display :99 (sin contraseña, solo escucha local; noVNC hace de puente web)
x11vnc -display :99 -nopw -forever -shared -rfbport 5900 -localhost >/tmp/x11vnc.log 2>&1 &
sleep 2

# 4) noVNC: web en 0.0.0.0:6080 (TODAS las interfaces incl. eth0; NO atar a la IP de eth0)
websockify --web=/usr/share/novnc 0.0.0.0:6080 localhost:5900 >/tmp/novnc.log 2>&1 &
sleep 2

echo "STACK_UP"
echo "  CDP   : http://127.0.0.1:9222"
echo "  noVNC : http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote (tras sbx ports)"
wait
