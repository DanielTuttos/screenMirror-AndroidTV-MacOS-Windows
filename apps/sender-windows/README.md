# 🪟 apps/sender-windows — Emisor para Windows

**Estado**: ⚪ no iniciado · **Lenguaje**: C# (.NET 8) · **mín. Windows 10 1903**

Captura la pantalla de Windows, codifica con NVENC y la envía a la TV por el protocolo de `docs/protocol.md`.

## Stack

- **Windows.Graphics.Capture** (captura de pantalla HW)
- **NVENC** vía *FFmpeg.AutoGen* (fallback: Media Foundation)
- **Makaretu.DnsSD** (descubrimiento mDNS)
- UI mínima en **bandeja del sistema** (WPF)
- Emparejamiento PIN → token

## Pipeline

```
Windows.Graphics.Capture → NVENC (H.264) → POST /stream (chunked) → TV
```

## Estructura prevista

```
ScreenMirror.Sender/
├── App/          # bandeja del sistema (WPF)
├── Domain/       # Device, Session, StreamConfig, StreamError (puros)
├── Capture/      # GraphicsCaptureItem → Direct3D11
├── Encode/       # H264Encoder (NVENC / Media Foundation)
├── Transport/    # StreamClient + DiscoveryClient (mDNS)
├── Pairing/      # PIN → token
└── Shared/       # Protocol.cs
```

## Pendiente

- [ ] Solución .NET 8 + proyecto WPF
- [ ] Captura + NVENC + `POST /stream`
- [ ] Descubrimiento mDNS + PIN
- [ ] Opción "iniciar con Windows" (opcional)
