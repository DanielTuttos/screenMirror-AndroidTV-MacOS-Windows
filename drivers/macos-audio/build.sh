#!/bin/bash
# Compila el driver de audio virtual «ScreenMirror TV» → drivers/macos-audio/build/ScreenMirrorAudio.driver
set -euo pipefail

cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

echo "Listo: $(pwd)/build/ScreenMirrorAudio.driver"
echo "Instálalo con: sudo ./install.sh"
