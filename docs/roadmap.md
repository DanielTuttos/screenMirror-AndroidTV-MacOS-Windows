# 🗺️ Roadmap de ScreenMirror

> Mantener actualizado desde cada sesión. El estado resumido vive en [`AGENTS.md` §2](../AGENTS.md).

## Fase 0 — Infraestructura ✅

- [x] Carpeta del proyecto con las 3 apps
- [x] `AGENTS.md` con contexto, reglas y protocolo de sesión
- [x] Docs: arquitectura, protocolo, decisiones, roadmap

## Fase 1 — Receptor mínimo + prueba de latencia (1–2 semanas)

Objetivo: validar **antes de invertir más** que la latencia es aceptable.

- [x] Scaffold Gradle de `receiver-tv` (Compose, pantalla completa, foreground service)
- [x] Servidor HTTP con endpoints `/status`, `/pair`, `/stream`, `/stream DELETE` → decodificación `MediaCodec` → `SurfaceView`
- [x] Emparejamiento con PIN + rate limit + tokens (24 h) — la spec decía fase 2, llegó antes porque `/stream` exige token
- [x] Soporte de cuerpos **chunked** (los envía ffmpeg)
- [x] Script de prueba `scripts/test-stream-mac.sh` (pair + ffmpeg → TV)
- [x] 24 tests unitarios en verde (parser, NALs, pairing, chunked)
- [x] **Instalar en la TV Android real** y medir latencia → **100–300 ms medidos** (TV Riviera 55", `192.168.10.63`, MediaTek `c2.mtk.avc.decoder`)
- [x] **Decidir (ADR-005): se sigue con HTTP+H.264** — la latencia cumple < 400 ms, no hace falta WebRTC aún

**Criterio de éxito**: vídeo del Mac en la TV con < 400 ms de latencia → ✅ **cumplido** (100–300 ms).

### Hallazgos de la prueba real (fase 1)

- El decoder MediaTek exige **perfil Baseline/Main/High 4:2:0**: `yuv420p` + `-profile:v baseline` obligatorios en el emisor (un `uyvy422` heredado → High 4:2:2 → `decode error 0xe` fatal y corte del stream).
- Frontera de AU = **`first_mb_in_slice == 0`**: agrupar un VCL por AU parte imágenes multi-slice y corrompe el vídeo (Mediatek: `no frame produced` + cola desbordada).
- `avfoundation` rechaza el framerate default 29.97 → `-framerate 30` en la entrada; timestamps rotos → filtro `fps=30` antes de escalar.
- Cuerpos con `Content-Length` necesitan `LimitedInputStream` (si no, el pump espera al cierre del emisor y las pruebas con curl tardan 30 s).
- `ffmpeg -list_devices` sale con código ≠ 0 por diseño → tolerar con `|| true` en scripts con `set -euo pipefail`.

## Fase 2 — Descubrimiento + emisor macOS (3–4 semanas)

- [x] Anuncio **mDNS** (`_screenmirror._tcp`) en el receptor (NsdManager, TXT `v=0 id=… pin=true name=…`) + emparejamiento **PIN**
- [x] `sender-macos`: ScreenCaptureKit → VideoToolbox → `POST /stream` (CLI `--cli`, validado E2E en la TV real)
- [x] Selector de pantalla con modo *espejo* / *extender* (ADR-006): captura la display que se elija (CLI: `--display`; GUI: lista de displays) → **pantalla virtual propia** (`--virtual [WxH]`, `CGVirtualDisplay*` vía shim, BetterDisplay eliminado) → **validado E2E en la TV real** (escritorio vacío)
- [x] Validar **2560×1440** en la TV real y decidir la resolución por defecto (ADR-007) → **ganó 1440p** (A/B con texto fino + `composition=DEVICE` al panel 4K)
- [x] Detección automática de la TV en la red — **lado emisor**: `ReceiverBrowser` (NWBrowser) + CLI `--discover`; E2E completo descubrir → emparejar → emitir sobre la IPv6 resuelta (falta enchufarlo a la GUI)
- [x] **Audio al TV** (ADR-008): `POST /audio` con PCM s16le 48 kHz · emisor `SCStream(capturesAudio)` · receptor `AudioTrack` → **validado E2E en la TV real** (25 s, 1,24 M muestras, sonido escuchado). Pendiente solo `sender-windows`
- [x] **Reconexión automática y cambio de resolución/orientación** (ADR-009): backoff 0.5→5 s + tokens persistidos + `DisplayWatcher` (callback CG + polling 2 s) → **validado E2E en la TV real**: receptor matado/relanzado reconectó sin re-parear; cambio 1440p→1080p→1440p re-emitió en cada paso
- [x] GUI del emisor (menú de barra): lista de TVs descubiertas + PIN + displays + toggle "pantalla virtual". El flujo de pantalla virtual está validado E2E por CLI; el toggle en sí falta probarlo a mano
- [ ] Token de sesión en Keychain (hoy solo vive en memoria/CLI)

**Criterio de éxito**: abrir el emisor en el Mac → aparece la TV → PIN → espejo funcionando. Y con una 2ª pantalla disponible → extender.

### Hallazgos sobre resolución en la TV real (2026-11-14)

- La TV Riviera tiene panel **4K**, pero Android compone a **1920×1080** (`FramebufferSurface 1920x1080`) y el escalador del panel sube a 4K.
- Causa: `ro.surface_flinger.max_graphics_width=1920` / `max_graphics_height=1080`, propiedades de **solo lectura** del fabricante → **no se pueden cambiar sin root + reinicio**.
- Esa misma propiedad limita `wm size`: cualquier ancho > 1920 se **escala proporcionalmente** (2560×1440 → 1920×1080, 1936×1080 → 1920×1071). `wm size reset` vuelve siempre a 1920×1080.
- **Vía abierta → RESUELTA**: la capa de vídeo reporta `forceClientComposition=false` y `displayFrame=[0 0 3840 2160]`, o sea que va a **plano de hardware**. Confirmado con un stream a 1440p: `composition=DEVICE`, `sourceCrop=[0 0 2560 1440]` → el escalador del panel sube a 4K desde 1440p. **A/B visual con texto fino (2026-11-14): 1440p se lee mejor que 1080p** → 1440p es la resolución por defecto.
- `screencap` devuelve siempre la resolución **lógica** (1920×1080): sirve para leer la UI, no para medir nitidez del panel.

### Hallazgos de displays virtuales y reconexión (2026-11-16)

- **`CGDisplayRegisterReconfigurationCallback` no se propaga entre procesos**: un cambio de resolución hecho por otro proceso (Ajustes, otra app, `CGDisplaySetDisplayMode` externo) **nunca** llega al callback registrado en el emisor. Verificado con un test propio (proceso dueño de la display vs. proceso externo). Por eso `DisplayWatcher` combina el callback (cambios propios, inmediatos) con **polling de `CGDisplayBounds` cada 2 s** (cambios externos).
- `CGDisplaySetDisplayMode` **revierte al salir el proceso que lo aplicó** ("persists for the life of the program"): para probar un cambio en caliente hay que mantener vivo el proceso que cambia el modo.
- API privada `CGVirtualDisplay*`: las 4 clases existen en el runtime (`NSClassFromString` las ve) pero **no están en los headers del SDK** → shim ObjC con solo declaraciones (derivable de DeskPad, MIT). `swift build` las resuelve enlazando contra CoreGraphics.
- Las displays virtuales BetterDisplay/propresas **se recrean con id nueva** cada aparición: el selector `--display` debe leer la lista fresca, no memorizar ids.
- `CGDisplayCopyAllDisplayModes`/`CGDisplaySetDisplayMode` (no "AllModes"/"SetMode") y en Swift las props `mode.width`/`mode.height` (las funciones `CGDisplayModeGetWidth` están obsoletas desde Swift 3).

### Hallazgos de descubrimiento mDNS (2026-11-14)

- `NsdServiceInfo` en Android moderno **exige** `serviceType` explícito: sin él `registerService` falla con *"Service type cannot be empty"* (el tipo que se pasa a `registerService` no basta).
- `mDNS` en el Mac puede resolver el servicio a la **IPv6 link-local** `fe80::…%en0` en vez de la IPv4.
- `URLComponents.host` **rechaza** zonas IPv6 (`%en0`) → `ReceiverClient.endpoint()` construye esa URL a mano con corchetes y `%25` escapado (RFC 6874). `URL(string:)` sí la acepta → HTTP 200.
- `NWBrowser.Result.Metadata` no tiene caso `.txt`: los registros llegan en `.bonjour(NWTXTRecord)`, que ya es un diccionario iterable (no hace falta parsear bytes DNS-STD).

## Fase 3 — Emisor Windows + audio (1–2 meses)

- [ ] `sender-windows`: Windows.Graphics.Capture + NVENC
- [x] Audio en macOS + receptor (ADR-008, fase 2) — queda el loopback de Windows (WASAPI)
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
