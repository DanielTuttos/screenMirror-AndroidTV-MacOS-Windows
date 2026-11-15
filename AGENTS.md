# 📌 AGENTS.md — Contexto y reglas de ScreenMirror

> **OBLIGATORIO**: leer este archivo completo al **inicio** de cada sesión de trabajo y **actualizarlo al final** (sección 2). Es la única fuente de verdad del estado del proyecto.
> Si la sesión arranca en una subcarpeta, navegar hasta la raíz del proyecto y leerlo igual.

---

## 1. Visión

**ScreenMirror** = suite de 3 apps, **gratuita, sin anuncios y sin caducidad**, para duplicar la pantalla de un Mac o Windows hacia una **TV Android** (tipo AirScreen, pero propia, libre y sin depender de nadie).

Pilares:

- **100% red local** → sin servidores, sin costes, sin suscripciones.
- **Open source** → el proyecto es tuyo para siempre.
- **Clean architecture + clean code** → fácil de leer, testear y ampliar.

### Limitaciones conocidas (NO resolver, no intentarlo)

| Límite | Motivo |
|---|---|
| No aparece en el menú AirPlay (macOS) ni en Win+K (Miracast) | Requieren certificación Apple / Wi-Fi Alliance. Tendrá su **propia lista de dispositivos** dentro de la app |
| Contenido DRM (Netflix, etc.) en negro | Restricción del propio contenido. **Prohibido** intentar by-pass (cuestión legal) |
| Latencia realista 150–400 ms (Wi-Fi 5 GHz) | Física de la red + codificación |

---

## 2. 🔴 Estado actual (ACTUALIZAR SIEMPRE AL FINAL DE CADA SESIÓN)

| Campo | Valor |
|---|---|
| Última actualización | 2026-11-14 |
| Fase | **2 — Descubrimiento + emisor macOS: 🟡 EN CURSO** (mDNS + E2E completos; quedan reconexión, aspect-ratio y polish GUI) |
| Siguiente paso | Reconexión automática y cambio de resolución/orientación → demo del **modo extendido** con una app de pantalla virtual (ADR-006) → token en Keychain |
| `apps/receiver-tv` | 🟢 compila · **29 tests en verde** · **validado en TV real** (Riviera 55" TPQ10, `192.168.10.63`, Android 14, MediaTek) · anuncia `_screenmirror._tcp` (verificado con `dns-sd` desde el Mac) · id de dispositivo permanente |
| `apps/sender-macos` | 🟢 compila · **15 tests en verde** · **E2E validado en la TV real**: `--discover` (mDNS) → PIN → emitir **2560×1440@30fps** → cierre limpio · CLI completo (`--discover --host --pin --token --display --max --fps --seconds`) · GUI de menú de barra con lista de TVs (falta probar a ojo) |
| `apps/sender-windows` | ⚪ no iniciado |
| Bloqueos | — |
| Último aprendido | `NsdServiceInfo` exige `serviceType` explícito (si no: *"Service type cannot be empty"*), y el mDNS del Mac puede resolver a **IPv6 link-local** `fe80::…%en0`: `URLComponents.host` la rechaza → `ReceiverClient.endpoint()` construye la URL a mano con corchetes y `%25` escapado (**RFC 6874**), verificado con HTTP 200. |

---

## 3. Estructura del proyecto

```
ScreenMirror/
├── AGENTS.md                 ← ESTE ARCHIVO (leer siempre)
├── README.md                 ← visión para humanos
├── .gitignore
├── docs/
│   ├── architecture.md       ← arquitectura limpia por app
│   ├── protocol.md           ← spec del protocolo emisor↔receptor (fuente de verdad)
│   ├── roadmap.md            ← fases con checkboxes
│   └── decisions.md          ← registro de decisiones (ADR)
├── scripts/
│   └── test-stream-mac.sh    ← prueba de latencia: Mac → TV con ffmpeg
└── apps/
    ├── receiver-tv/          ← Android TV (Kotlin) — receptor
    ├── sender-macos/         ← macOS (Swift) — emisor
    └── sender-windows/       ← Windows (C#) — emisor
```

**Regla de oro**: `docs/protocol.md` es la fuente de verdad del protocolo. Las 3 apps lo implementan; si cambia, se actualiza el doc **y** las 3 apps en la misma sesión.

---

## 4. Arquitectura

### Diagrama general

```
┌──────────────────────────┐        ┌──────────────────────────┐
│  EMISOR (Mac/Windows)    │  HTTP  │  RECEPTOR (Android TV)   │
│  Capture → Encode → Send │ ─────▶ │  Recv → Decode → Surface │
│  (ScreenCaptureKit /     │        │  (MediaCodec + SurfaceView│
│   Graphics.Capture +     │◀───────│   + mDNS + PIN)          │
│   VideoToolbox / NVENC)  │ control└──────────────────────────┘
└──────────────────────────┘
```

### Capas de cada app (clean architecture)

```
ui/         → pantalla, estado, interacción (sin lógica de negocio)
domain/     → modelos puros + casos de uso (sin dependencias de plataforma)
data/       → implementaciones (red, almacenamiento) que implementan interfaces de domain
core/       → infraestructura compartida: Protocol.*, pipeline de vídeo, logging, errores
```

Flujo: `ui → caso de uso → interfaz (domain) → impl (data) → core`.

### Pila por app

| App | Lenguaje | Stack | Mín. |
|---|---|---|---|
| receiver-tv | Kotlin | Compose (material3) + MediaCodec + NsdManager + ForegroundService | Android TV, minSdk 24 |
| sender-macos | Swift | SwiftUI (menú de barra) + ScreenCaptureKit + VideoToolbox | macOS 13 |
| sender-windows | C# | .NET 8 + Windows.Graphics.Capture + NVENC (FFmpeg.AutoGen) | Windows 10 1903 |

---

## 5. Protocolo (resumen — spec completa en `docs/protocol.md`)

- **v0 (MVP)**: HTTP/1.1 sobre TCP en la red local, puerto **9471**.
- Descubrimiento por **mDNS**: `_screenmirror._tcp`.
- Emparejamiento con **PIN de 6 dígitos** → token de sesión.
- Cuerpo del stream: **H.264 Annex-B** con SPS/PPS inline, keyframe cada 2 s.
- **v1 (futuro)**: WebRTC (P2P + audio) y control de calidad.

---

## 6. Reglas de código (CLEAN CODE)

### Generales (aplican a las 3 apps)

1. **Inglés** para identificadores de código; **español** para docs, commits y comentarios que expliquen el *por qué*.
2. Nada de comentarios que repitan el código. Solo el **por qué** cuando no sea obvio.
3. Un archivo = una responsabilidad. Archivos < ~300 líneas.
4. Funciones pequeñas, un solo nivel de abstracción (< ~40 líneas).
5. Nombres descriptivos (`pairingServer`, nunca `handler2`).
6. Capas estrictas: `ui → domain → data → core`. El **domain no conoce** Android, Apple ni Windows.
7. Errores explícitos: prohibido `catch {}` vacío o excepciones tragadas. Usar errores tipados.
8. **YAGNI**: no implementar nada que la fase actual no necesite. Sin código "por si acaso".
9. El protocolo vive en **un único archivo por app**: `Protocol.kt` / `Protocol.swift` / `Protocol.cs`.
10. **Prohibido**: by-pass de DRM, implementar AirPlay, Miracast o Cast certificado.
11. Commits convencionales: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`.
12. Cada fase termina con algo **ejecutable/demo**. Nada de código huérfano.
13. Tests unitarios obligatorios para parsing del protocolo y lógica de `domain/`.
14. **Latencia > features**: si compiten, gana el rendimiento del stream.
15. Documentación viva: cualquier cambio de arquitectura o protocolo se refleja en `docs/` y en este archivo.

### Kotlin (receptor-tv)

- Kotlin + coroutines; **DI manual** (sin Hilt hasta que duela): la raíz es `core/ReceiverContainer`.
- Un solo `Activity` con **Compose (material3)** y un `SurfaceView` alojado vía `AndroidView`.
- `MediaCodec` en **modo síncrono sobre un `HandlerThread` dedicado** (más legible que async+cola): nunca en el hilo principal. La red solo encola AUs, jamás bloquea.
- Foreground service para recibir 24/7 (arranque automático con el TV).
- Package raíz: `tv.screenmirror.receiver`.

### Swift (sender-macos)

- Swift 5.9+, captura con **ScreenCaptureKit**, codificación con **VideoToolbox** (hardware).
- App de **menú de barra** (sin icono en el Dock).
- Package/raíz: `ScreenMirrorSender`.

### C# (sender-windows)

- **.NET 8**, UI mínima en bandeja del sistema.
- Captura con `Windows.Graphics.Capture`, codificación **NVENC** vía FFmpeg.AutoGen.
- Namespace raíz: `ScreenMirror.Sender`.

---

## 7. Decisiones y roadmap

- Decisiones (ADR): [`docs/decisions.md`](docs/decisions.md)
- Fases y tareas: [`docs/roadmap.md`](docs/roadmap.md)

---

## 8. 🔁 Protocolo de sesión (cómo trabajar aquí)

1. **Leer este archivo completo.**
2. Leer `docs/roadmap.md` y ubicar la fase actual.
3. Trabajar aplicando las reglas de la sección 6.
4. Si se cambia el protocolo → actualizar `docs/protocol.md` + las 3 apps + este archivo.
5. **Al finalizar la sesión, actualizar la sección 2** de este archivo:
   - fecha, fase, siguiente paso, estado de cada app,
   - decisiones nuevas (en `decisions.md`),
   - y el campo **"Último aprendido"** con el hallazgo más relevante.
6. Mantener este archivo con las **mejores prácticas actuales**: si aparece una mejor forma de hacer algo, actualizar las reglas de la sección 6 en lugar de acumular excepciones.

---

_Última revisión de buenas prácticas: 2026-01-13_
