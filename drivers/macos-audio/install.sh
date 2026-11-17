#!/bin/bash
# Instala (o con -u, desinstala) el driver de audio «ScreenMirror TV».
# Requiere root porque copia a /Library y reinicia coreaudiod (el audio del Mac se corta ~1 s).
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Ejecútalo con sudo: sudo $0 [-u]"
    exit 1
fi

cd "$(dirname "$0")"
install_dir="/Library/Audio/Plug-Ins/HAL"
driver="ScreenMirrorAudio.driver"

restart_audio_server() {
    echo "-- Reiniciando coreaudiod"
    launchctl kickstart -k system/com.apple.audio.coreaudiod || killall -9 coreaudiod
}

if [ "${1:-}" = "-u" ]; then
    echo "-- Desinstalando ${driver}"
    rm -rf "${install_dir}/${driver}"
    restart_audio_server
    exit 0
fi

if [ ! -d "build/${driver}" ]; then
    echo "No existe build/${driver}: ejecuta antes ./build.sh"
    exit 1
fi

echo "-- Instalando ${driver}"
rm -rf "${install_dir}/${driver}"
cp -R "build/${driver}" "${install_dir}/"
restart_audio_server
echo "-- Listo: «ScreenMirror TV» ya aparece en Ajustes › Sonido › Salida"
