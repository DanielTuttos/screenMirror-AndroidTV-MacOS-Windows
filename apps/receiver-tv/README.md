# 📱 apps/receiver-tv — Receptor para Android TV

**Estado**: 🟡 estructura planificada · **Lenguaje**: Kotlin (100% nativo) · **ADR-002**

Receptor **siempre activo**: al encender el TV la app ya escucha, anuncia su servicio por mDNS y espera el stream del emisor.

## Stack

- Kotlin + Coroutines + Compose (material3; tv-material cuando haya controles focusables)
- `MediaCodec` (decodificación HW, modo síncrono en `HandlerThread`) → `SurfaceView`
- Servidor HTTP propio (sin frameworks) + `ChunkedInputStream` (ffmpeg usa chunked)
- minSdk 24 · paquete `tv.screenmirror.receiver`

## Estructura prevista (clean architecture)

```
app/src/main/java/tv/screenmirror/receiver/
├── ui/          # Compose (material3) + ReceiverViewModel (StateFlow)
├── domain/      # modelos puros + casos de uso + interfaces (sin Android)
├── data/        # HttpStreamServer, MdnsAdvertiser, PairingStore
├── core/        # VideoPipeline (MediaCodec), Protocol.kt, Result tipado, logging
└── service/     # ReceiverService (foreground)
```

## Fase 1 (objetivo de validación)

1. Scaffold Gradle + pantalla completa + foreground service.
2. `POST /stream` → `MediaCodec` → `SurfaceView`.
3. Probar con `ffmpeg` desde el Mac y **medir latencia**.
4. Decidir: seguir con HTTP o pasar a WebRTC (ADR-005).

```bash
# Prueba manual desde el Mac (fase 1)
ffmpeg -f avfoundation -capture_cursor 1 -i "<index_pantalla>" \
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 8M \
  -g 60 -f h264 "http://<ip-tv>:9471/stream?token=TEST&w=1920&h=1080&fps=30"
```

## Estado

**🟢 Fase 1 en curso**: compila, 23 tests en verde, APK debug generado en
`app/build/outputs/apk/debug/app-debug.apk`.

```bash
# Instalar en la TV (con depuración USB o red activada)
adb install -r app/build/outputs/apk/debug/app-debug.apk

# Desde el Mac: prueba de latencia (PIN visible en la pantalla de la TV)
./scripts/test-stream-mac.sh <ip-tv> <pin>
```

## Pendiente

- [x] Proyecto Gradle + tests
- [x] `HttpStreamServer` + `VideoPipeline` + `AnnexBAccessUnitReader`
- [x] UI de estado (PIN / recibiendo con stats / detenido)
- [ ] Prueba en TV real + medición de latencia
- [ ] mDNS (aparecer solo en la red) — fase 2
