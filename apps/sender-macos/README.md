# 🍎 apps/sender-macos — Emisor para macOS

**Estado**: 🟢 completo / pulido · **Lenguaje**: Swift · **mín. macOS 14.2**

Captura la pantalla del Mac, codifica en hardware (VideoToolbox) y la envía a la TV por el protocolo de `docs/protocol.md`.

## Stack

- **ScreenCaptureKit** (captura) → `CVPixelBuffer`
- **VideoToolbox** (H.264 HW, zerolatency, rate limits contra picos de red, 30 / 60 fps)
- **Core Audio Tap** + Driver propio HAL (`ScreenMirrorAudio.driver`) para audio condicional
- **Network.framework** (transporte HTTP chunked sin buffer innecesario)
- SwiftUI en **menú de barra** (sin Dock): lista de TVs detectadas, PIN, selector de pantalla/resolución/fluidez
- Emparejamiento con PIN → token guardado en **Keychain** (`KeychainTokenStore`)
- Pantalla virtual propia con shim `CGVirtualDisplay*` (modo extender sin hardware extra)

## Pipeline

```
ScreenCaptureKit → VideoToolbox (H.264 HW) ──┐
                                             ├─▶ HTTP chunked ──▶ TV Android
SystemAudioTap (Core Audio) ─────────────────┘
```

## Estructura

```
ScreenMirrorSender/
├── App/          # SenderApp (MenuBarExtra), SenderView, SenderViewModel
├── CLI/          # CLIStreamer (soporte de línea de comandos para tests y headless)
├── Domain/       # TokenStore, DiscoveredReceiver, DisplayDescriptor, StreamConfig, SenderError
├── Capture/      # ScreenCaptureHandler, VirtualDisplay, SystemAudioTap, PCMAudioConverter, DisplayWatcher
├── Encode/       # H264Encoder (VideoToolbox)
├── Storage/      # KeychainTokenStore, AudioDriverConnection
├── Transport/    # StreamClient, ReceiverClient, ReceiverBrowser (mDNS)
├── Session/      # StreamSession (reconexión automática con backoff), ReconnectPolicy
├── Resources/    # Info.plist, AppIcon.icns
└── Shared/       # Protocol.swift
```

## Empaquetado y Distribución (.app y .dmg)

Para generar la aplicación ejecutable `ScreenMirror.app` y el instalador `ScreenMirror-Installer.dmg`:

```bash
# Desde la raíz del repositorio:
./scripts/package-mac-dmg.sh
```

El script se encarga de:
1. Compilar el proyecto en modo **Release** (`swift build -c release`).
2. Crear la estructura del bundle `ScreenMirror.app` con su `Info.plist` e icono `AppIcon.icns`.
3. Firmar el bundle ad-hoc con `codesign`.
4. Generar el archivo `dist/ScreenMirror-Installer.dmg` con enlace a `/Applications` mediante `hdiutil`.

Resultado generado en:
```
dist/
├── ScreenMirror.app
└── ScreenMirror-Installer.dmg
```
