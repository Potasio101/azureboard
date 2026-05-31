#!/bin/bash
# Apaga la pila VNC (Xvfb + Chromium + x11vnc + noVNC) levantada por debug-stack.sh.
#
# IMPORTANTE: ejecútalo como ARCHIVO (`bash kill-stack.sh`), NO pegues estos pkill
# sueltos en la tool Bash: si el patrón aparece en la cmdline del comando, pkill -f
# se manda SIGTERM a sí mismo (exit 144). Como archivo, la cmdline es solo la ruta
# del script y no coincide con los patrones, así que es seguro.
pkill -f "Xvfb :99"
pkill -f "user-data-dir=/tmp/chrome-profile"
pkill -x x11vnc
pkill -f "websockify --web"
pkill -f "login-watch.cjs"
pkill -f "debug-stack.sh"
sleep 2
rm -rf /tmp/chrome-profile

# Verificación por PUERTOS (no por nombre de proceso, para no auto-matarse)
echo "CDP 9222 :"; curl -s --max-time 4 http://127.0.0.1:9222/json/version >/dev/null 2>&1 && echo "  AÚN RESPONDE" || echo "  apagado"
echo "noVNC6080:"; curl -s --max-time 4 -o /dev/null http://127.0.0.1:6080/vnc.html 2>&1 && echo "  AÚN RESPONDE" || echo "  apagado"
echo "display  :"; DISPLAY=:99 timeout 3 xdpyinfo >/dev/null 2>&1 && echo "  :99 ACTIVO" || echo "  :99 apagado"
echo
echo "No olvides cerrar el puerto en el HOST:  sbx ports <SANDBOX_VM_ID> --unpublish 6080:6080/tcp"
