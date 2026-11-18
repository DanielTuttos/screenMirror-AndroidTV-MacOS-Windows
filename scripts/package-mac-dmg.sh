#!/bin/bash
# Script para empaquetar ScreenMirror (macOS) en .app y generar un instalador .dmg
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"
SENDER_DIR="${ROOT_DIR}/apps/sender-macos"
DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="ScreenMirror"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-Installer.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
TEMP_DMG_DIR="/tmp/screenmirror_dmg_pack"

echo "==> 1. Compilando ScreenMirrorSender en modo Release..."
swift build -c release --package-path "${SENDER_DIR}"

BIN_PATH="$(swift build -c release --package-path "${SENDER_DIR}" --show-bin-path)/ScreenMirrorSender"

if [ ! -f "${BIN_PATH}" ]; then
    echo "Error: No se encontró el binario en ${BIN_PATH}"
    exit 1
fi

echo "==> 2. Creando la estructura del paquete ${APP_NAME}.app..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copiar ejecutable
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/ScreenMirrorSender"
chmod +x "${APP_BUNDLE}/Contents/MacOS/ScreenMirrorSender"

# Copiar Info.plist e Icono
cp "${SENDER_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
if [ -f "${SENDER_DIR}/Resources/AppIcon.icns" ]; then
    cp "${SENDER_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

echo "==> 3. Firmando la aplicación ad-hoc..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> 4. Preparando contenido para el instalador DMG..."
rm -rf "${TEMP_DMG_DIR}"
mkdir -p "${TEMP_DMG_DIR}"

# Copiar App
cp -R "${APP_BUNDLE}" "${TEMP_DMG_DIR}/"

# Enlace simbólico a /Applications para arrastrar y soltar
ln -s /Applications "${TEMP_DMG_DIR}/Aplicaciones"

echo "==> 5. Creando imagen de disco .dmg..."
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${TEMP_DMG_DIR}" -ov -format UDZO "${DMG_PATH}"

rm -rf "${TEMP_DMG_DIR}"

echo ""
echo "============================================================"
echo "✔ ¡Instalador DMG generado con éxito!"
echo "Ubicación: ${DMG_PATH}"
echo "============================================================"
