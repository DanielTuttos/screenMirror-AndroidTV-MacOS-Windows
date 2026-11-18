# ScreenMirror 📺

**Gratuito · Sin anuncios · Sin caducidad · 100% red local**

Suite de 3 apps para duplicar la pantalla de tu **Mac** o **Windows** hacia una **TV Android**, al estilo de AirScreen pero propia, libre y sin depender de servidores ni suscripciones.

## Apps

| App | Plataforma | Estado | Descripción |
|---|---|---|---|
| [`apps/receiver-tv`](apps/receiver-tv) | Android TV (Kotlin) | 🟢 completada | Receptor: siempre activo, anuncia su servicio por mDNS, recibe H.264/PCM a 60 fps y lo reproduce en pantalla completa |
| [`apps/sender-macos`](apps/sender-macos) | macOS (Swift) | 🟢 completada | Emisor: menú de barra, captura con VideoToolbox (30/60 fps, hasta 1440p), audio con driver virtual propio, pantalla virtual |
| [`apps/sender-windows`](apps/sender-windows) | Windows (C#) | ⚪ pendiente | Emisor: ídem para Windows (Fase 3: Windows.Graphics.Capture + NVENC) |

## Documentación

- 📌 [`AGENTS.md`](AGENTS.md) — contexto, reglas de código y estado (se lee en cada sesión)
- 🏗️ [`docs/architecture.md`](docs/architecture.md) — arquitectura limpia por app
- 🔌 [`docs/protocol.md`](docs/protocol.md) — protocolo emisor ↔ receptor
- 🗺️ [`docs/roadmap.md`](docs/roadmap.md) — fases del proyecto
- 🧭 [`docs/decisions.md`](docs/decisions.md) — decisiones tomadas (ADR)

## Cómo funciona

```
Mac/Windows ──(captura + codificación HW)──▶ HTTP/H.264 ──▶ TV Android (decodifica y pinta)
                         ▲                                     │
                         └───────── mDNS + PIN/QR ─────────────┘
```

Sin servidores: ambos extremos hablan directamente en tu red local.

## Límites conocidas

- **No aparecerá** en el menú AirPlay de macOS ni en Win+K (Miracast): esos protocolos exigen certificación. Tendrá su **propia lista** dentro de la app.
- **DRM** (Netflix, etc.): se ve en negro, igual que en cualquier app de esta categoría.
- Latencia realista: **150–400 ms** en Wi-Fi 5 GHz.

## Construcción y Empaquetado

### Emisor macOS (`.dmg`)
Para empaquetar la app de macOS en `ScreenMirror.app` y generar su instalador `ScreenMirror-Installer.dmg`:
```bash
./scripts/package-mac-dmg.sh
```
El archivo queda en `dist/ScreenMirror-Installer.dmg`.

### Receptor Android TV (`.apk`)
Para compilar e instalar el APK de depuración en la TV mediante ADB:
```bash
cd apps/receiver-tv
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Estado actual

Fase **2 — Descubrimiento + emisor macOS** completada y pulida (stream a 60 fps @ 1440p, audio dinámico con driver HAL propio, pantalla virtual propia, empaquetado en `.dmg` y `.apk`). Siguiente: Fase 3 (`sender-windows`). Detalle en [`AGENTS.md` §2](AGENTS.md).
