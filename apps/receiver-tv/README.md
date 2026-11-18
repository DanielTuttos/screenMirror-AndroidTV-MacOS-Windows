# 📱 apps/receiver-tv — Receptor para Android TV

**Estado**: 🟢 completo y validado en TV real · **Lenguaje**: Kotlin (100% nativo) · **ADR-002**

Receptor **siempre activo**: al encender el TV la app ya escucha, anuncia su servicio por mDNS y espera el stream del emisor.

## Stack

- Kotlin + Coroutines + Jetpack Compose (material3)
- `MediaCodec` (decodificación HW de H.264, baja latencia, soporte 60 fps) → `SurfaceView` alojado en `AndroidView`
- `AudioTrack` en modo STREAM con buffer de baja latencia + `PcmFrameAligner` (PCM s16le sin estática ni chasquidos)
- Servidor HTTP propio sin frameworks (`HttpStreamServer`) en puerto 9471 con soporte Chunked
- Persistencia de emparejamiento y tokens en `SharedPreferences`
- Descubrimiento mDNS con `NsdManager` (`_screenmirror._tcp`)
- minSdk 24 · paquete `tv.screenmirror.receiver`

## Estructura (Clean Architecture)

```
app/src/main/java/tv/screenmirror/receiver/
├── ui/          # Compose (MainActivity, ReceiverScreen, PinOverlay, ReceiverViewModel)
├── domain/      # Modelos puros (StreamRequest, AudioRequest, Outcome, ReceiverError) e interfaces
├── data/        # HttpStreamServer, HttpRequestParser, NsdAdvertiser, SharedPrefsPairingRepository
├── core/        # VideoPipeline (MediaCodec), AudioPipeline (AudioTrack + PcmFrameAligner), Protocol.kt
└── service/     # ReceiverService (foreground)
```

## Estado y Validación

🟢 **44 tests unitarios en verde** (`./gradlew testDebugUnitTest`).
Validado de extremo a extremo en TV real (Riviera 55" 4K TPQ10, Android 14, MediaTek):
- Vídeo fluido a **60 fps @ 2560×1440 (1440p)**.
- HUD discreto de FPS en la esquina inferior izquierda.
- Audio alineado sin ruido de chasquidos.

```bash
# Compilar e instalar en la TV
cd apps/receiver-tv
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Pendiente

- [x] Proyecto Gradle + tests
- [x] `HttpStreamServer` + `VideoPipeline` + `AnnexBAccessUnitReader`
- [x] UI de estado (PIN / recibiendo con stats / detenido)
- [ ] Prueba en TV real + medición de latencia
- [ ] mDNS (aparecer solo en la red) — fase 2
