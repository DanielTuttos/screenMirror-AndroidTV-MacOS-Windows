#!/usr/bin/env bash
# Emite la pantalla del Mac hacia el receptor ScreenMirror (fase 1: prueba de latencia).
#
# Uso: ./scripts/test-stream-mac.sh <ip-tv> <pin> [ancho] [alto]
#   VIDEO_DEVICE  índice de dispositivo avfoundation (por defecto 1 = pantalla)
set -euo pipefail

TV_IP_RAW="${1:-}"
TV_IP="${TV_IP_RAW%%:*}" # se tolera "ip" o "ip:puerto"
PIN="${2:-}"
WIDTH="${3:-1280}"
HEIGHT="${4:-720}"
# Bitrate proporcional a los píxeles: 8 Mbps @1080p es la referencia validada en fase 1.
# A 1440p hacen falta ~14 Mbps o el texto de la pantalla extendida sale borroso.
BASE_BR_KBPS=8000
BR_KBPS="${5:-$((BASE_BR_KBPS * WIDTH * HEIGHT / (1920 * 1080)))}"
PORT=9471
# Dispositivo de captura: si no se especifica, se busca la pantalla ("Capture screen").
# ffmpeg -list_devices sale con código != 0 por diseño: se tolera con `|| true`.
if [[ -z "${VIDEO_DEVICE:-}" ]]; then
  DEVICE_LIST=$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true)
  VIDEO_DEVICE=$(printf '%s\n' "$DEVICE_LIST" \
    | sed -n 's/.*\[\([0-9][0-9]*\)\] Capture screen.*/\1/p' | head -1)
  VIDEO_DEVICE="${VIDEO_DEVICE:-0}"
fi

if [[ -z "$TV_IP" || -z "$PIN" ]]; then
  echo "Uso: ./scripts/test-stream-mac.sh <ip-tv> <pin> [ancho] [alto] [bitrate-kbps]"
  echo "Ejemplo: ./scripts/test-stream-mac.sh 192.168.1.50 123456 2560 1440"
  exit 1
fi

echo "==> Emparejando con la TV (PIN $PIN)…"
RESPONSE=$(curl -sS --max-time 5 -X POST "http://$TV_IP:$PORT/pair" \
  -H 'Content-Type: application/json' \
  -d "{\"pin\":\"$PIN\"}")

TOKEN=$(printf '%s' "$RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [[ -z "$TOKEN" ]]; then
  echo "Fallo al emparejar: $RESPONSE"
  exit 1
fi

echo "==> Token obtenido. Enviando pantalla (${WIDTH}x${HEIGHT} @ ${BR_KBPS} kbps)…"
echo "    (Ctrl+C para cortar)"
# fps=30 fuerza timestamps constantes: sin él, la captura de pantalla emite timestamps
# rotos y x264 calcula un nivel absurdo en el SPS que el decoder de la TV rechaza.
# -framerate 30 va en la entrada: el default 29.97 lo rechazan los devices de avfoundation.
ffmpeg -hide_banner -loglevel warning \
  -f avfoundation -framerate 30 -capture_cursor 1 -i "$VIDEO_DEVICE:none" \
  -vf "fps=30,scale=${WIDTH}:${HEIGHT}" \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -pix_fmt yuv420p -profile:v baseline \
  -b:v "${BR_KBPS}k" -g 60 -bf 0 \
  -f h264 "http://$TV_IP:$PORT/stream?token=$TOKEN&w=$WIDTH&h=$HEIGHT&fps=30&keyint=60&br=$BR_KBPS"
