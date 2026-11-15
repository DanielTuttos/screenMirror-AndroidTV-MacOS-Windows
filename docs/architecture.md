# 🏗️ Arquitectura de ScreenMirror

> Objetivo: **clean architecture**, dependencias hacia adentro, fácil de entender y de testear.
> Reglas generales en [`AGENTS.md` §6](../AGENTS.md).

## Principios

1. **Capas estrictas**: `ui → domain → data → core`. Solo se permite dependencia hacia dentro.
2. **`domain` puro**: modelos y casos de uso sin Android, Swift ni Windows. Testeable en JVM puro.
3. **Interfaces en `domain`, implementaciones en `data`**: la UI depende de abstracciones.
4. **El protocolo es compartido**: una única especificación (`docs/protocol.md`) y una única clase de constantes por app (`Protocol.*`).
5. **Un flujo, un pipeline**: `capturar → codificar → enviar → recibir → decodificar → pintar`, sin atajos ni lógica escondida en la UI.

## 1. `apps/receiver-tv` — Android TV (Kotlin)

```
tv.screenmirror.receiver/
├── ScreenMirrorApp.kt       # Application: raíz de composición (DI manual)
├── ui/                      # sin lógica de negocio
│   ├── MainActivity.kt      # pantalla completa + arranca el servicio
│   ├── ReceiverViewModel.kt # expone ReceiverState y publica la Surface
│   └── ReceiverScreen.kt    # SurfaceView + overlay de PIN + HUD de stats
├── domain/                  # puro, sin Android
│   ├── Outcome.kt           # Success/Failure tipado (nada de excepciones silenciadas)
│   ├── ReceiverError.kt     # errores tipados
│   ├── model/               # ReceiverState, StreamStats, StreamRequest
│   ├── repository/          # interfaces: PairingRepository, StreamServer
│   └── runtime/             # interface ReceiverRuntime (fachada de la UI)
├── data/                    # implementaciones
│   ├── http/                # HttpStreamServer, HttpRequestParser, ChunkedInputStream,
│   │                        # HttpResponse, StreamRequestParser
│   ├── pairing/             # PairingStore (PIN + tokens + rate limit)
│   └── ReceiverRuntimeImpl.kt
├── core/                    # infraestructura compartida
│   ├── Protocol.kt          # ÚNICO punto con constantes del protocolo
│   ├── VideoSurface.kt      # registro de la Surface (UI → pipeline)
│   ├── ReceiverContainer.kt # raíz de composición
│   └── stream/              # VideoPipeline (MediaCodec) + AnnexBAccessUnitReader
└── service/
    └── ReceiverService.kt   # foreground service: receptor vivo 24/7
```

> **Nota (fase 1)**: no existe carpeta `usecase/` — se sigue YAGNI: la UI usa `ReceiverRuntime` como fachada. Se añadirán casos de uso cuando la UI crezca. Tampoco hay `mdns/` ni `prefs/`: llegan en la fase 2.

**Hilos**: `ReceiverService`/UI (main) → servidor en `Dispatchers.IO` → `VideoPipeline` con `HandlerThread` propio. La UI solo observa `StateFlow`.

**Flujo de datos**:

```
Red (POST /stream) → HttpStreamServer → VideoPipeline (MediaCodec) → SurfaceView
                          │
                          └→ ReceiverRuntimeImpl → ReceiverViewModel → UI (estado + stats)
```

## 2. `apps/sender-macos` — macOS (Swift)

```
ScreenMirrorSender/
├── App/                    # SwiftUI menú de barra: lista de TVs, botón conectar, ajustes
├── Domain/                 # modelos puros: Device, Session, StreamConfig, StreamError
├── Capture/                # ScreenCaptureHandler (ScreenCaptureKit) → CVPixelBuffer
├── Encode/                 # H264Encoder (VideoToolbox, low-latency, keyframe 2 s)
├── Transport/              # StreamClient (URLSession/NWConnection) + DiscoveryClient (mDNS)
├── Pairing/                # PIN → token, almacenamiento en Keychain
└── Shared/Protocol.swift   # constantes del protocolo
```

**Pipeline**: `ScreenCaptureKit → VideoToolbox → HTTP POST /stream` en este orden, sin pasar por disco.

## 3. `apps/sender-windows` — Windows (C# / .NET 8)

```
ScreenMirror.Sender/
├── App/                    # bandeja del sistema (WPF mínimo)
├── Domain/                 # modelos y casos de uso puros
├── Capture/                # GraphicsCaptureItem → Direct3D11 surface
├── Encode/                 # NVENC vía FFmpeg.AutoGen (o Media Foundation como fallback)
├── Transport/              # HttpClient + mDNS (Makaretu.DnsSD)
├── Pairing/                # PIN → token
└── Shared/Protocol.cs
```

**Mismo pipeline**: `Windows.Graphics.Capture → NVENC → HTTP POST /stream`.

## Decisiones transversales

| Tema | Decisión | ADR |
|---|---|---|
| Transporte MVP | HTTP chunked + H.264 Annex-B | ADR-005 |
| Transporte futuro | WebRTC si la latencia de fase 1 > 400 ms | ADR-005 |
| Descubrimiento | mDNS `_screenmirror._tcp` | — |
| Seguridad | PIN 6 dígitos → token aleatorio; solo LAN | — |
| Servidor | Sin frameworks pesados: servidor HTTP mínimo propio (1 endpoint de stream) | — |
| DI | Manual (constructores explícitos) | — |

## Calidad

- **Tests unitarios** en `domain/` (JVM puro): parsing del protocolo, emparejamiento, errores.
- **Tests de integración**: `curl`/`ffplay` contra el receptor en el emulador o TV.
- **Métricas visibles** en la TV: fps, bitrate, latencia estimada (necesarias para la fase 1).
