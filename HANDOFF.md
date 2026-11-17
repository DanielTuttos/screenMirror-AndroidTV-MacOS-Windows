# 📋 HANDOFF.md — Traspaso para la próxima IA / sesión

> **LEER ESTE ARCHIVO AL INICIO DE LA SESIÓN** (junto con `AGENTS.md`, que es la fuente de verdad del estado). Contiene el contexto completo actualizado: qué se hizo, en qué se estaba trabajando, qué falta y todos los trucos del entorno. Cuando la fase avance, este documento se archiva/actualiza y manda `AGENTS.md`.
>
> **Fecha del traspaso**: 2026-11-16 · **Último commit**: `8b798b4` · **Hay cambios SIN commitear** (ver §4).

---

## 1. Qué es el proyecto

**ScreenMirror**: suite de **3 apps gratuitas** (sin anuncios, sin caducidad, 100% red local, open source) para duplicar/extender la pantalla de un Mac o Windows hacia una **TV Android**:

| App | Lenguaje | Estado |
|---|---|---|
| `apps/receiver-tv` | Kotlin (Compose + MediaCodec + mDNS) | 🟢 validado en TV real · **40 tests en verde** |
| `apps/sender-macos` | Swift (SwiftUI menú de barra + ScreenCaptureKit + VideoToolbox) | 🟢 E2E validado en TV real · **19 tests en verde** |
| `apps/sender-windows` | C# (.NET 8) | ⚪ no iniciado |

**Reglas obligatorias** (resumen de `AGENTS.md` §6 — léelo completo):
- Inglés para identificadores, español para docs/comentarios del *por qué*.
- `docs/protocol.md` = fuente de verdad del protocolo; si cambia → doc + las 3 apps.
- Clean architecture (`ui → domain → data → core`), archivos < ~300 líneas, YAGNI, errores explícitos (nada de `catch {}` vacío).
- Commits convencionales: `feat:` `fix:` `docs:` `refactor:` `test:`.
- Prohibido: by-pass de DRM, implementar AirPlay/Miracast/Cast certificado.
- **Al final de cada sesión**: actualizar `AGENTS.md` §2 (fecha, fase, apps, tests, "Último aprendido").

Decisiones clave (detalle en `docs/decisions.md`): ADR-001 HTTP+H.264 propio en puerto 9471 · ADR-006 pantalla virtual propia con API privada `CGVirtualDisplay*` (shim derivado de DeskPad MIT; BetterDisplay ya **desinstalado**) · ADR-007 techo 1440p · ADR-008 audio PCM aparte (`POST /audio`) · ADR-009 reconexión con backoff + `DisplayWatcher` (callback CG + polling 2 s).

---

## 2. Dónde está el proyecto ahora (commiteado, verde)

Todo lo del §antecedentes está commiteado en `8b798b4`:

- **Fase 2 casi completa**: descubrimiento mDNS (`--discover` y también enchufado a la GUI vía `ReceiverBrowser`), emparejamiento PIN → token, stream vídeo 2560×1440@30fps, audio PCM, **reconexión automática** (backoff 0.5→5 s, tokens persistidos en `SharedPreferences` del receptor, cambio de resolución en caliente re-emitiendo), **modo extendido con pantalla virtual propia** (`--virtual [WxH]`, sin BetterDisplay).
- **CLI completa** del emisor: `--discover --host --pin --token --display --virtual --max --fps --no-audio --seconds`.
- **GUI de menú de barra existe** (`SenderApp`/`SenderView`/`SenderViewModel`): lista de TVs mDNS + IP manual + PIN/Emparejar + lista de displays + botón Emitir/Detener. **Falta probarla a ojo** y le faltaba el botón de pantalla virtual (ver §4).

### Prueba E2E ya hecha y válida (no repetir salvo regresión)

- Reconexión: matar el proceso receptor → 5 reintentos con backoff → relanzar → re-emite sin re-parear.
- Cambio de resolución en caliente: 1440p→1080p→1440p re-emitiendo en cada paso.
- Pantalla virtual propia: crea display (ids volátiles), emite escritorio vacío a la TV (overlay "RECIBIENDO" de `ReceiverScreen.kt` confirma stream), la retira al salir.

---

## 3. En qué se estaba trabajando (siguiente objetivo: GUI del emisor)

**Objetivo en curso**: terminar la GUI del menú de barra → **añadir el botón "pantalla virtual"** (objetivo pedido por el usuario: "lista de TVs descubiertas + PIN + displays + botón pantalla virtual").

### Hecho en esta sesión (compila + 19 tests verdes, pero **SIN commitear**)

1. **`Capture/VirtualDisplay.swift`** — nuevo `convenience init(name:size:)` que construye los modos comunes `2560x1440, 1920x1080, 1600x900, 1280x720` (el pedido primero). Compartido por CLI y GUI.
2. **`CLI/CLIStreamer.swift`** — usa el init compartido; eliminada su copia privada `virtualModes(_:)`.
3. **`App/SenderViewModel.swift`**:
   - `@Published private(set) var virtualDisplay: VirtualDisplay?` (nil = no creada).
   - `setVirtualDisplay(enabled:)`: al crear → `VirtualDisplay(name:"ScreenMirror", size:(2560,1440))`, selecciona su id y refresca; **guard**: si `isStreaming` → aviso "Detén la emisión antes de crear la pantalla virtual." Al apagar → si se emite *desde* la virtual, `await session.stop()` y luego `releaseVirtualDisplay()`; si no, suelta directo. `releaseVirtualDisplay()` pone `virtualDisplay = nil` (deinit → macOS retira la display) + `selectedDisplayID = nil` + `refreshDisplays()`.
   - `refreshDisplays()` mejorado: **preserva la selección** si la pantalla sigue existiendo (si no → vuelve a la principal); reintenta **una vez a los 500 ms** si la virtual recién creada aún no aparece en `SCShareableContent`.
4. **`App/SenderView.swift`** — en el `GroupBox("Pantalla")`, `Toggle("Pantalla virtual (extender)")` con `Binding(get: { model.virtualDisplay != nil }, set: { model.setVirtualDisplay(enabled: $0) })`, estilo `.switch`, + caption "Escritorio vacío en la TV: se crea una 2ª pantalla en este Mac."

### Verificado hasta donde se paró

- `swift build` → Build complete · `swift test` → **19 tests, 0 fallos**.
- La **GUI arranca**: proceso vivo, icono `airplayvideo` aparece en la barra de menús (verificado por diff de screenshots con/sin proceso).
- Se abrió el menú con `osascript` (funciona, ver §6) pero **la captura final salió con una notificación de Google Meet tapando la zona y NO se pudo verificar visualmente el toggle nuevo**. → **Esa es la primera tarea pendiente** (§4).

---

## 4. 🔴 Pendiente inmediato (por eso está sin commitear)

1. **Ver visualmente la GUI** con el toggle "Pantalla virtual (extender)":
   - Lanzar: `swift run ScreenMirrorSender` (o el bin de `.build`).
   - Esperar ~4 s → icono `airplayvideo` en la barra de menús (esquina superior derecha, ≈x=1764 px físicos en tu pantalla 2560×1440).
   - Abrir menú con: `osascript -e 'tell application "System Events" to tell (first process whose name is "ScreenMirrorSender") to click menu bar item 1 of menu bar 2'` → `screencapture -x` → recortar zona `(1450, 0, 2560, 900)` con PIL y **leer la imagen**.
   - **Trampas**: una notificación (Meet/calendario) puede tapar la zona → esperar y reintentar; el menú se cierra al hacer clic fuera.
   - Idealmente: **pedir al usuario que pulse el icono y diga qué ve** (más fiable que la automatización).
2. **Probar el toggle a ojo**: encender → aparece "ScreenMirror 2560x1440 · extender" en la lista de displays y se selecciona sola → Emitir → TV muestra escritorio vacío → Detener → apagar toggle → la display virtual desaparece del Mac.
3. Si todo OK → **commit** `feat: botón de pantalla virtual en la GUI del emisor` + actualizar `AGENTS.md` §2 (+ roadmap: casilla GUI) y **archivar/actualizar este HANDOFF**.
4. Después (orden del roadmap): **token en Keychain** (hoy los tokens solo viven en memoria/CLI), pulir GUI (estado al reconectar ya soportado: `.reconnecting` se muestra), luego **fase 3: `sender-windows`** (+ loopback WASAPI).

---

## 5. Contexto del entorno de pruebas (TV real)

- **TV**: Riviera 55" TPQ10, Android 14 (MediaTek), IP **`192.168.10.63`**, receptor puerto **9471**.
- **adb**: `adb connect 192.168.10.63:5555` (a veces se cae → `adb disconnect` y reconectar; los comandos largos con adb pueden colgar → timeout amplio).
- **APK debug**: `apps/receiver-tv/app/build/outputs/apk/debug/app-debug.apk`.
- **PIN/token vigentes**: PIN `038087` · token `aaa0223e13e45a60ee4ccc4f4b0288544dbb709f4f559ea5f0063d5ab630b919` (24 h desde emisión). Cada relanzamiento del receptor genera **PIN nuevo**; los **tokens persisten** (SharedPreferences) así que no hay que re-parear.
- **La TV se va a screensaver** → receptor en background → `SurfaceView` sin superficie → `POST /stream` devuelve **HTTP 503 `NoDisplay`** (NO es bug del emisor). Despertar antes de emitir:
  ```
  adb -s 192.168.10.63:5555 shell input keyevent KEYCODE_WAKEUP
  adb -s 192.168.10.63:5555 shell input keyevent KEYCODE_HOME
  adb -s 192.168.10.63:5555 shell "monkey -p tv.screenmirror.receiver -c android.intent.category.LAUNCHER 1"
  ```
  Y verificar que `topResumedActivity=…tv.screenmirror.receiver/.ui.MainActivity`.
- **`adb screencap` poco fiable**: a veces frame congelado o mezcla Mac+TV → dos capturas seguidas y comparar md5; si idénticas → pedir PIN/confirmación al usuario.

### E2E estándar del emisor (CLI)

```bash
cd apps/sender-macos
swift run ScreenMirrorSender --discover                      # lista TVs
swift run ScreenMirrorSender --cli --host 192.168.10.63 --token <TOKEN> [--virtual] [--seconds 25]
# logs en /private/var/folders/j0/qsgh05px2hv9z3c9jcfr29b00000gn/T/opencode/*.txt
# filtrar fps: tr '\r' '\n' < log | grep -vE "^ *[0-9]+ fps"
```

---

## 6. Hallazgos técnicos clave (no redescubrir)

1. **`CGDisplayRegisterReconfigurationCallback` NO se propaga entre procesos**: un cambio hecho por otro proceso nunca llega al callback. Por eso `DisplayWatcher` = callback CG (cambios propios, inmediatos) + **polling de `CGDisplayBounds` cada 2 s** (externos) + debounce 0,5 s. Verificado con test propio aislado (`/private/var/folders/…/opencode/vdwatch/`).
2. **`CGDisplaySetDisplayMode` revierte al salir del proceso que lo aplicó** ("persists for the life of the program"): para probar cambios en caliente, mantener vivo el proceso *changer* (`Thread.sleep`).
3. **API privada `CGVirtualDisplay*`**: las 4 clases existen en runtime pero **no en headers del SDK** → shim ObjC con solo declaraciones (`Sources/CGVirtualDisplayShim`, derivado de Stengo/DeskPad **MIT**, atribuido en la cabecera). `CGVirtualDisplay(descriptor:)` **no es failable** en Swift (importado como no-optional); `apply(settings)` devuelve Bool y es el que falla.
4. **Displays virtuales**: se recrean con **id nueva** cada vez → leer id fresco del log (`grep -o 'id [0-9]*'`), nunca memorizar. Al morir el objeto `VirtualDisplay`, macOS la retira sola (sin `terminate()` explícito — ojo, la doc de DeskPad sí lo llama; aquí funciona por deinit, validado E2E).
5. **APIs de modo**: `CGDisplayCopyAllDisplayModes(display, nil)` + `CGDisplaySetDisplayMode(display, mode, nil)` (¡NO `CGDisplayCopyAllModes`/`CGDisplaySetMode`!); en Swift usar props `mode.width`/`mode.height` (`CGDisplayModeGetWidth` obsoleto desde Swift 3).
6. **Shell tool bloquea `$(…)`**: usar scripts intermedios en `/private/var/folders/j0/qsgh05px2hv9z3c9jcfr29b00000gn/T/opencode/` y escapar `\$0` en heredocs sin comillas.
7. **Para ver la GUI por código**: `osascript` con System Events **funciona** (accessibility concedido) → `click menu bar item 1 of menu bar 2` del proceso `ScreenMirrorSender`; después `screencapture -x` + PIL para recortar. El nombre del menú aparece como "Video De Airplay".
8. **Tests**: Swift → `swift test` en `apps/sender-macos` (19). Kotlin → `./gradlew testDebugUnitTest -q` en `apps/receiver-tv` y contar con `grep -h -o 'tests="[0-9]*"' app/build/test-results/testDebugUnitTest/*.xml` (40); fallos: `grep -l 'failures="[1-9]' …`.
9. `CGGetActiveDisplayList` para listar displays rápido desde un `swift -e`.

---

## 7. Estructura del emisor (dónde mirar)

```
apps/sender-macos/Sources/ScreenMirrorSender/
├── main.swift                 ← --cli → CLIStreamer; si no → SenderApp (menú de barra)
├── App/  SenderApp.swift · SenderView.swift · SenderViewModel.swift   ← GUI (en edición)
├── CLI/  CLIStreamer.swift    ← flags: --discover --host --pin --token --display --virtual --max --fps --no-audio --seconds
├── Capture/ ScreenCaptureHandler · H264Encoder(Encode/) · VirtualDisplay · DisplayWatcher · PCMAudioConverter · SystemAudioFormat
├── Session/ StreamSession (connect/reconnect/stop) · ReconnectPolicy (backoff/isFatal)
├── Transport/ ReceiverBrowser (NWBrowser mDNS) · ReceiverClient (pair/status) · StreamClient
├── Domain/ DiscoveredReceiver · DisplayDescriptor · ReceiverStatus · SenderError · StreamConfig
└── Shared/ Protocol.swift     ← único archivo de protocolo de la app
```

Flujo UI: `SenderView → SenderViewModel → ReceiverClient / StreamSession / ScreenCaptureHandler / VirtualDisplay`.

---

## 8. Estado de los tests y compilación (2026-11-16)

| Proyecto | Compila | Tests |
|---|---|---|
| `apps/receiver-tv` | 🟢 | 🟢 **40** |
| `apps/sender-macos` | 🟢 (con cambios de GUI sin commitear) | 🟢 **19** |

**Cambios sin commitear** (revisar con `git status --short` antes de tocar nada):
`App/SenderView.swift`, `App/SenderViewModel.swift`, `CLI/CLIStreamer.swift`, `Capture/VirtualDisplay.swift`.
