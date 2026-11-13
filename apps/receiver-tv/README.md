# 📱 apps/receiver-tv — Receptor para Android TV

**Estado**: 🟡 estructura planificada · **Lenguaje**: Kotlin (100% nativo) · **ADR-002**

Receptor **siempre activo**: al encender el TV la app ya escucha, anuncia su servicio por mDNS y espera el stream del emisor.

## Stack

- Kotlin + Coroutines + Compose for TV
- `MediaCodec` (decodificación HW) → `SurfaceView`
- `NsdManager` (mDNS) · `ForegroundService` (24/7) · DI manual
- minSdk 24 · paquete `tv.screenmirror.receiver`

## Estructura prevista (clean architecture)

```
app/src/main/java/tv/screenmirror/receiver/
├── ui/          # Compose for TV + ReceiverViewModel (StateFlow)
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

## Pendiente

- [ ] Proyecto Gradle
- [ ] `HttpStreamServer` + `VideoPipeline`
- [ ] UI de estado (esperando conexión / emitiendo / stats)
- [ ] mDNS + PIN (fase 2)
