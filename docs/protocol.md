# 🔌 Protocolo ScreenMirror

> **Fuente de verdad**. Las 3 apps lo implementan; cualquier cambio se actualiza aquí **y** en `Protocol.kt` / `Protocol.swift` / `Protocol.cs` en la misma sesión.
> Versionado: cambios incompatibles suben el número de versión (`v=0` → `v=1`).

## v0 — MVP (HTTP + H.264)

**Estado**: borrador estable · **Transporte**: HTTP/1.1 sobre TCP · **Puerto**: `9471` · **Red**: solo LAN

### Descubrimiento (mDNS)

| Campo | Valor |
|---|---|
| Tipo de servicio | `_screenmirror._tcp.local` |
| Nombre | nombre de la TV (ej. `TV Salón`) |
| Puerto | `9471` |
| TXT | `v=0`, `id=<uuid-permanente>`, `name=<nombre>`, `pin=true` |

El emisor **enumera** los servicios y muestra la lista en su UI (ese es el "menú" de la app).

### Emparejamiento

1. La TV muestra un **PIN de 6 dígitos** (y opcionalmente un QR).
2. El emisor envía el PIN; la TV devuelve un **token** aleatorio de 256 bits.
3. Todo `/stream` posterior exige el token.
4. Rate limit: **5 intentos/min** por IP → `429`. Tokens caducan a las **24 h**.

### Endpoints

#### `GET /status`

Respuesta `200 application/json`:

```json
{
  "app": "ScreenMirror Receiver",
  "proto": 0,
  "name": "TV Salon",
  "id": "uuid",
  "maxW": 2560,
  "maxH": 1440,
  "codec": "h264",
  "busy": false
}
```

`maxW`/`maxH` es el **techo absoluto** que acepta el receptor: por encima responde `413`. El emisor debe reducir la resolución hasta encajar (nunca escalar hacia arriba).

#### `POST /pair`

Body: `{"pin":"123456"}` → `200`:

```json
{ "token": "<hex-256bits>", "ttl": 86400 }
```

Errores: `401` PIN incorrecto · `429` rate limit.

#### `POST /stream`

Query params:

| Param | Obligatorio | Default | Descripción |
|---|---|---|---|
| `token` | ✅ | — | token de /pair |
| `w` `h` | ✅ | — | resolución del stream |
| `fps` | ❌ | `30` | fotogramas por segundo |
| `keyint` | ❌ | `60` | frames entre keyframes (2 s @ 30 fps) |
| `br` | ❌ | `8000` | bitrate objetivo en kbps |

Headers: `Content-Type: video/avc; annexb`

**Body**: stream **H.264 Annex-B** continuo (SPS/PPS inline antes de cada IDR, IDR cada `keyint` frames).

Respuesta inmediata `200` con cuerpo vacío; el stream sigue hasta que el emisor cierra la conexión.
Si la TV ya está emitiendo vídeo → `409 {"error":"busy"}`.

#### `POST /audio`

Query params:

| Param | Obligatorio | Default | Descripción |
|---|---|---|---|
| `token` | ✅ | — | token de /pair |
| `sr` | ❌ | `48000` | sample rate (Hz): 44100 o 48000 |
| `ch` | ❌ | `2` | canales: 1 (mono) o 2 (estéreo) |

Headers: `Content-Type: audio/pcm`

**Body**: stream **PCM raw 16-bit little-endian** continuo.

Respuesta inmediata `200` con cuerpo vacío; el stream sigue hasta que el emisor cierra la conexión.
Es una conexión TCP concurrente e independiente de `/stream`. Si no se conecta `/audio`, el receptor reproduce solo vídeo.
Si la TV ya tiene una sesión de audio activa → `409 {"error":"busy"}`.

#### `DELETE /stream?token=...`

Cierra la sesión de emisión actual → `204`.

### Códigos de error

| Código | Significado |
|---|---|
| `401` | token/PIN inválido |
| `403` | versión de protocolo incompatible |
| `409` | stream ocupado |
| `413` | resolución superior a la soportada |
| `429` | rate limit de emparejamiento |
| `500` | error interno (el emisor debe reintentar con backoff) |

### Reglas de stream

- **Latencia objetivo**: < 300 ms totales.
- Codificación del emisor: H.264, **zerolatency**, sin B-frames, `keyint` 60.
- El receptor decodifica con `MediaCodec` → `SurfaceView` (sin escritura a disco, sin buffers largos: descartar frame si el decoder va tarde).
- Cierre de conexión = fin de sesión (no hace falta `DELETE`).

## v1 — Futuro (no implementar aún)

- **WebRTC** (P2P, audio Opus/AAC, latencia ~150 ms) — sustituye o complementa HTTP (ADR-005).
- Control de calidad adaptativo (cambiar bitrate sobre la marcha).
- Eventos de control emisor ↔ receptor (`/events`, SSE): pause, resolución, stats.
- Múltiples emisores simultáneos.
