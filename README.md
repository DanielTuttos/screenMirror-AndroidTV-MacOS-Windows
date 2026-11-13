# ScreenMirror 📺

**Gratuito · Sin anuncios · Sin caducidad · 100% red local**

Suite de 3 apps para duplicar la pantalla de tu **Mac** o **Windows** hacia una **TV Android**, al estilo de AirScreen pero propia, libre y sin depender de servidores ni suscripciones.

## Apps

| App | Plataforma | Estado | Descripción |
|---|---|---|---|
| [`apps/receiver-tv`](apps/receiver-tv) | Android TV (Kotlin) | 🟡 planificada | Receptor: siempre activo, anuncia su servicio por mDNS, recibe H.264 y lo pinta a pantalla completa |
| [`apps/sender-macos`](apps/sender-macos) | macOS (Swift) | ⚪ pendiente | Emisor: captura la pantalla, codifica en HW y la envía a la TV |
| [`apps/sender-windows`](apps/sender-windows) | Windows (C#) | ⚪ pendiente | Emisor: ídem para Windows |

## Documentación

- 📌 [`AGENTS.md`](AGENTS.md) — contexto, reglas de código y estado (se lee en cada sesión)
- 🏗️ [`docs/architecture.md`](docs/architecture.md) — arquitectura limpia por app
- 🔌 [`docs/protocol.md`](docs/protocol.md) — protocolo emisor ↔ receptor
- 🗺️ [`docs/roadmap.md`](docs/roadmap.md) — fases del proyecto
- 🧭 [`docs/decisions.md`](docs/decisions.md) — decisiones tomadas (ADR)

## Cómo funciona

```
Mac/Windows ──(captura + codificación HW)──▶ HTTP/H.264 ──▶ TV Android (decodifica y pinta)
                         ▲                                     │
                         └───────── mDNS + PIN/QR ─────────────┘
```

Sin servidores: ambos extremos hablan directamente en tu red local.

## Límites conocidas

- **No aparecerá** en el menú AirPlay de macOS ni en Win+K (Miracast): esos protocolos exigen certificación. Tendrá su **propia lista** dentro de la app.
- **DRM** (Netflix, etc.): se ve en negro, igual que en cualquier app de esta categoría.
- Latencia realista: **150–400 ms** en Wi-Fi 5 GHz.

## Estado actual

Fase **0 — Infraestructura** completada. Siguiente: scaffold del receptor y prueba de latencia. Detalle en [`AGENTS.md` §2](AGENTS.md).
