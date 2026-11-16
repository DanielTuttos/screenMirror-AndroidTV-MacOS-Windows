# 🧭 Decisiones (ADR)

Registro de decisiones arquitectónicas. Formato: **Contexto → Decisión → Consecuencias**.
Nueva entrada al final; no borrar las anteriores (a menos que se revoque, indicándolo).

---

## ADR-001 — Protocolo propio HTTP + H.264 (no Miracast/AirPlay/Cast)

- **Fecha**: 2026-01-13
- **Contexto**: queremos que la TV "aparezca" en los menús del sistema, pero AirPlay (Apple) y Miracast (Wi-Fi Alliance) exigen certificación; Cast certificado exige contrato con Google. Imposible para un proyecto propio.
- **Decisión**: crear un **protocolo propio** sobre HTTP en la red local (ver `protocol.md`) con **emisor y receptor propios**. La TV tendrá su **propia lista de dispositivos** dentro de la app.
- **Consecuencias**: no se integra con los menús del sistema (aceptado); control total, sin dependencias de terceros, coste 0.

## ADR-002 — Receptor en Kotlin nativo (no Expo/React Native)

- **Fecha**: 2026-01-13
- **Contexto**: el receptor necesita `MediaCodec` de baja latencia, `SurfaceView`, `NsdManager` y un servicio 24/7. Expo no expone nada de esto sin módulos nativos propios.
- **Decisión**: receptor **100% nativo en Kotlin**. Expo queda descartado para este proyecto.
- **Consecuencias**: máximo control y rendimiento; sin reutilizar el ecosistema RN (aceptado).

## ADR-003 — 100% red local, sin servidores

- **Fecha**: 2026-01-13
- **Contexto**: objetivo de que sea gratis para siempre y sin caducidad.
- **Decisión**: emisor y receptor hablan **directamente en la LAN** (mDNS + HTTP). Ningún componente en la nube.
- **Consecuencias**: coste 0 € y privacidad total; solo funciona en la misma red (aceptado).

## ADR-004 — Distribución por APK firmado (sideload)

- **Fecha**: 2026-01-13
- **Contexto**: publicar en Google Play cuesta 25 $ una vez y exige políticas de divulgación para captura de pantalla.
- **Decisión**: distribuir **APK firmado directamente** (0 €). Play Store como opción futura.
- **Consecuencias**: instalación manual en la TV (activar "fuentes desconocidas"); sin revisión de Google.

## ADR-005 — MVP en HTTP chunked, WebRTC como evolución

- **Fecha**: 2026-01-13 · **Resolución**: 2026-11-14
- **Contexto**: WebRTC es mejor en latencia y audio, pero añade mucha complejidad (libwebrtc, signaling, ICE) desde el minuto cero.
- **Decisión**: empezar con **H.264 Annex-B sobre HTTP chunked**. En la **fase 1 se mide la latencia**; si supera 400 ms, se evalúa saltar a WebRTC antes de seguir.
- **Resolución (fase 1)**: latencia medida **100–300 ms** en la TV real (Riviera 55" MediaTek, Wi-Fi) → **se mantiene HTTP**. WebRTC queda para el protocolo v1 (audio P2P + menor latencia), no por el MVP.
- **Consecuencias**: MVP rápido y debuggeable con `curl`/`ffplay`; posible reescritura de transporte si falla el criterio (no falló).

## ADR-006 — Modo "extender": selector de pantalla, no API privada

- **Fecha**: 2026-11-14
- **Contexto**: el usuario quiere **extender** el escritorio (dejar contenido en la TV y seguir trabajando en el Mac), no solo duplicarlo. Extender exige una **segunda pantalla** en el macOS, y **no existe API pública de macOS para crear pantallas virtuales**; solo API privada (`CGVirtualDisplay*`, no expuesta ni siquiera como símbolo en esta versión de macOS), hardware (clavija dummy, monitor) o software de terceros.
- **Decisión**: el emisor tendrá un **selector de pantalla** (enumera las displays con `SCShareableContent` y captura la que se elija) con dos modos: *espejo* (pantalla principal) y *extender* (cualquier otra display). La **segunda pantalla la aporta el usuario** con una app de terceros tipo BetterDisplay/MacVirtualDisplay, un monitor o una clavija dummy. ~~No integramos API privada en el proyecto~~ *(anulado el 2026-11-16: ver re-resolución abajo — pantalla virtual propia con API privada)*.
- **Consecuencias**: el mismo código sirve para las 3 fuentes de pantalla; coste 0 si ya se tiene hardware; el usuario instala la app que prefiera (único paso manual); si algún día Apple publica una API, se puede sustituir sin tocar el protocolo.
- **Resolución (2026-11-15, validado)**: probado con **BetterDisplay 5.2.1** (cask de Homebrew, capa gratuita crea pantallas virtuales por CLI: `betterdisplaycli create -type=VirtualScreen …`). Emitiendo la display virtual a la TV se ve un **escritorio vacío en la TV** = modo extendido real (no espejo). El selector `--display <id>` del emisor captura cualquier display sin cambios de código (ADR-006 sin deuda pendiente).
- **Re-resolución (2026-11-16)**: se **elimina BetterDisplay** (desinstalado) y el emisor crea su **propia pantalla virtual** con `CGVirtualDisplay*` vía el shim `Sources/CGVirtualDisplayShim` (interfaces derivadas de Stengo/DeskPad, MIT). Se acepta **API privada** de Apple para este caso puntual: es el mismo mecanismo de DeskPad/BetterDisplay/OpenDisplay, no hay API pública (verificada en el SDK: ausente) y la app se distribuye por sideload, no por App Store. El shim es un único header: si Apple publica API oficial, se sustituye sin tocar el resto del código. CLI: `--virtual [WxH]` crea la display, la emite y la retira al salir. Validado E2E en la TV: escritorio vacío + cambio de resolución en caliente detectado (vía polling, ver ADR-009).

## ADR-007 — Resolución del stream: techo en 2560×1440

- **Fecha**: 2026-11-14
- **Contexto**: se quiere "mejor resolución" para leer texto en la pantalla extendida. La TV Riviera tiene panel **4K**, pero su Android compone a **1080p** por la propiedad de fábrica `ro.surface_flinger.max_graphics_width=1920` (solo lectura), que además limita `wm size` a 1920 de ancho.
- **Decisión**: subir el techo del receptor a **2560×1440** (resolución objetivo del escritorio extendido) y **no prometer 4K**. La posible ganancia por encima de 1080p depende de que la capa de vídeo vaya a **plano de hardware** en vez de componerse en el framebuffer de 1080p: se validará **a ojo con texto fino** antes de fijar la resolución por defecto.
- **Consecuencias**: el protocolo admite hasta 1440p (`maxW`/`maxH` en `/status`); si la TV compone todo a 1080p, se vuelve a 1920×1080 para no gastar CPU y ancho de banda en vano (regla *latencia > features*).
- **Resolución (2026-11-14, validado)**: **A/B a ojo con texto fino (8–12 px) en la TV real → 2560×1440 se lee claramente mejor que 1920×1080.** Confirmado además en `dumpsys SurfaceFlinger`: la capa de vídeo reporta `composition=DEVICE` con `sourceCrop=[0 0 2560 1440]` y `displayFrame=[0 0 3840 2160]`, o sea que va a **plano de hardware** y el escalador del panel la sube a 4K desde 1440p, saltándose el techo de composición de 1080p. **El emisor usa la resolución nativa de la display (hasta 2560×1440) por defecto.**

## ADR-008 — Audio: PCM crudo en un endpoint aparte (no dentro del vídeo)

- **Fecha**: 2026-11-15
- **Contexto**: falta transmitir el sonido del Mac a la TV. Opciones: (a) AAC/Opus multiplexado en el mismo stream HTTP, (b) WebRTC completo, (c) un segundo endpoint HTTP con PCM crudo.
- **Decisión**: **`POST /audio` concurrente con `/stream`**, cuerpo **PCM s16le 48 kHz estéreo** (lo que fija `SystemAudioFormat` del emisor). El emisor usa `ScreenCaptureKit` con `capturesAudio`; el receptor escribe directo a `AudioTrack`.
- **Consecuencias**:
  - Latencia de audio añadida ≈ buffer del AudioTrack (~60 ms) — imperceptible y dentro del techo de 300 ms.
  - Cero CPU de códec en ambos extremos (regla *latencia > features*); ~1,5 Mbps, despreciable en LAN.
  - El audio es **opcional por spec**: si `/audio` no abre (409, red), el emisor sigue emitiendo solo vídeo.
  - Dos conexiones TCP en vez de una; el servidor ya servía conexiones concurrentes, así que el coste es cero.
  - Si algún día se necesita reducir ancho de banda o sincronizar A/V con precisión, se cambia a AAC con timestamp en v1 (no rompe la spec si se añade un `codec=` al query).

## ADR-009 — Reconexión automática con backoff + polling de display

- **Fecha**: 2026-11-16
- **Contexto**: la sesión se cae por motivos habituales en TV (el sistema mata el proceso del receptor, la red titubea, cambia la resolución u orientación de la pantalla). Sin reconexión, el usuario debe re-parear a mano.
- **Decisión**:
  - **Reconexión del emisor**: si la sesión activa cae, `StreamSession` reintenta con backoff exponencial 0.5/1/2/4/5 s (`ReconnectPolicy`). Errores **fatales** (permiso de pantalla denegado, token caducado, pantalla ida, PIN rechazado) cortan con su mensaje en vez de reintentar para siempre.
  - **Tokens persistidos en el receptor** (`TokenStorage` + `SharedPreferences`): la TV puede matar el proceso del receptor y el emisor reconecta sin re-parear (TTL 24 h).
  - **Cambio de resolución/orientación**: `DisplayWatcher` detecta el cambio y reinicia la sesión con el tamaño nuevo. **Hallazgo**: `CGDisplayRegisterReconfigurationCallback` **no se propaga entre procesos** (verificado con test propio: un cambio hecho por otro proceso nunca llega al callback registrado) → se combina el callback (cambios del propio proceso, reacción inmediata) con **polling de `CGDisplayBounds` cada 2 s** (cambios externos: Ajustes del sistema, otras apps).
- **Consecuencias**: la TV puede reiniciarse o dormirse sin cortar la emisión (validado E2E: proceso matado a T=14 s, reconectado a T=22 s sin re-parear); una resolución cambia en ≤2,5 s (poll 2 s + debounce 0,5 s); el polling cuesta una comparación de CGRect cada 2 s (despreciable). El receptor no cambia: su `finally` ya liberaba el stream en EOF/RST.
