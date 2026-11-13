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

- **Fecha**: 2026-01-13
- **Contexto**: WebRTC es mejor en latencia y audio, pero añade mucha complejidad (libwebrtc, signaling, ICE) desde el minuto cero.
- **Decisión**: empezar con **H.264 Annex-B sobre HTTP chunked**. En la **fase 1 se mide la latencia**; si supera 400 ms, se evalúa saltar a WebRTC antes de seguir.
- **Consecuencias**: MVP rápido y debuggeable con `curl`/`ffplay`; posible reescritura de transporte si falla el criterio.
