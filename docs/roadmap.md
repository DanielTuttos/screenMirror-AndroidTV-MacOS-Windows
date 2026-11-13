# 🗺️ Roadmap de ScreenMirror

> Mantener actualizado desde cada sesión. El estado resumido vive en [`AGENTS.md` §2](../AGENTS.md).

## Fase 0 — Infraestructura ✅

- [x] Carpeta del proyecto con las 3 apps
- [x] `AGENTS.md` con contexto, reglas y protocolo de sesión
- [x] Docs: arquitectura, protocolo, decisiones, roadmap

## Fase 1 — Receptor mínimo + prueba de latencia (1–2 semanas)

Objetivo: validar **antes de invertir más** que la latencia es aceptable.

- [ ] Scaffold Gradle de `receiver-tv` (Compose for TV, pantalla completa, foreground service)
- [ ] Servidor HTTP con endpoint `/stream` → decodificación `MediaCodec` → `SurfaceView`
- [ ] Script `ffmpeg` de prueba que empuje H.264 Annex-B desde el Mac
- [ ] **Medir latencia real** y decidir si seguimos con HTTP o vamos directo a WebRTC

**Criterio de éxito**: vídeo del Mac en la TV con < 400 ms de latencia.

## Fase 2 — Descubrimiento + emisor macOS (3–4 semanas)

- [ ] Anuncio **mDNS** (`_screenmirror._tcp`) + emparejamiento **PIN**
- [ ] `sender-macos`: ScreenCaptureKit → VideoToolbox → `POST /stream`
- [ ] Detección automática de la TV en la red (aparece en la lista de la app)
- [ ] Reconexión automática y cambio de resolución/orientación

**Criterio de éxito**: abrir el emisor en el Mac → aparece la TV → PIN → espejo funcionando.

## Fase 3 — Emisor Windows + audio (1–2 meses)

- [ ] `sender-windows`: Windows.Graphics.Capture + NVENC
- [ ] Audio: loopback (WASAPI en Windows, CoreAudio en macOS) → reproduce la TV
- [ ] Control de calidad (bitrate adaptativo) y reintentos
- [ ] Emparejamiento con QR para no teclear el PIN

## Fase 4 — Pulido y publicación (1–2 meses)

- [ ] APK firmado + instalación por sideload (0 €) — Play Store opcional (25 $)
- [ ] Arranque automático con el TV, configuración, logs útiles
- [ ] README público, licencia MIT, capturas de vídeo

## Fase 5 — Opcional / futuro

- [ ] Emisor Android (`MediaProjection`)
- [ ] Protocolo **v1: WebRTC** (P2P + audio + menor latencia)
- [ ] Múltiples TVs y multi-emisor
