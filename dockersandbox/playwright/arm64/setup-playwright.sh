#!/bin/bash
# Setup del MCP de Playwright en Docker Sandbox ARM64.
# Idempotente: puedes correrlo varias veces. Ver ../README.md sección 2.
set -e

echo "==> [1/4] Comprobando arquitectura"
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "!! Este script es para ARM64; detectado: $ARCH. Aborta." >&2
  exit 1
fi

echo "==> [2/4] Instalando Chromium empaquetado (Google Chrome no existe en ARM64)"
npx playwright install chromium

CHROMIUM_BIN=$(ls -d "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux/chrome 2>/dev/null | sort -V | tail -1)
if [ -z "$CHROMIUM_BIN" ]; then
  echo "!! No encuentro el binario de Chromium tras la instalación." >&2
  exit 1
fi
echo "    Chromium: $CHROMIUM_BIN"

echo "==> [3/4] Symlink a /opt/google/chrome/chrome (ruta que espera el MCP)"
sudo mkdir -p /opt/google/chrome
sudo ln -sf "$CHROMIUM_BIN" /opt/google/chrome/chrome

echo "==> [4/4] Instalando dependencias de sistema"
if ! sudo npx playwright install-deps chromium 2>/tmp/install-deps.err; then
  echo "    apt falló; reparando listas corruptas y reintentando..."
  sudo rm -rf /var/lib/apt/lists/*
  sudo apt-get update
  sudo npx playwright install-deps chromium
fi

echo
echo "==> Verificación"
MISSING=$(ldd /opt/google/chrome/chrome 2>/dev/null | grep -c "not found" || true)
echo "    libs faltantes: $MISSING (debe ser 0)"
/opt/google/chrome/chrome --version || true
echo
echo "OK. El MCP de Playwright (mcp__playwright__browser_*) debería funcionar en headless."
echo "Para el modo VNC compartido, ver debug-stack.sh y ../README.md sección 3."
