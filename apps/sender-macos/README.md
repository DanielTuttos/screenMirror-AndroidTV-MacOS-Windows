# 🍎 apps/sender-macos — Emisor para macOS

**Estado**: ⚪ no iniciado · **Lenguaje**: Swift · **mín. macOS 13**

Captura la pantalla del Mac, codifica en hardware y la envía a la TV por el protocolo de `docs/protocol.md`.

## Stack

- **ScreenCaptureKit** (captura, macOS 12.3+) → `CVPixelBuffer`
- **VideoToolbox** (H.264 HW, zerolatency, keyint 60)
- **Network.framework / URLSession** (transporte HTTP)
- SwiftUI en **menú de barra** (sin Dock): lista de TVs detectadas, conectar, ajustes
- Emparejamiento con PIN → token guardado en **Keychain**

## Pipeline

```
ScreenCaptureKit → VideoToolbox (H.264 HW) → POST /stream (chunked) → TV
```

Sin disco, sin buffers intermedios grandes. Bitrate configurable (default 8 Mbps, 1080p30).

## Estructura prevista

```
ScreenMirrorSender/
├── App/          # SwiftUI menú de barra
├── Domain/       # Device, Session, StreamConfig, StreamError (puros)
├── Capture/      # ScreenCaptureHandler
├── Encode/       # H264Encoder (VideoToolbox)
├── Transport/    # StreamClient + DiscoveryClient (mDNS)
├── Pairing/      # PIN → token (Keychain)
└── Shared/       # Protocol.swift
```

## Pendiente

- [ ] Proyecto Xcode (o Tuist/Swift Package)
- [ ] Captura + codificación + `POST /stream`
- [ ] Descubrimiento mDNS + PIN
- [ ] Arranque automático al iniciar sesión (opcional)
