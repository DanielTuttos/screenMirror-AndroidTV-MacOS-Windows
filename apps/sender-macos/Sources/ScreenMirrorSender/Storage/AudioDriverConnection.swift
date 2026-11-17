import Foundation

/// Mantiene una conexión a través de un socket Unix local con el driver de audio
/// (`ScreenMirrorAudio.driver`).
/// Mientras esta conexión esté activa, el driver registra y publica «ScreenMirror TV»
/// en Core Audio. Cuando la conexión se cierra (o la app termina/se cierra), el driver
/// retira el dispositivo de inmediato del sistema.
final class AudioDriverConnection {
    private static let socketPath = "/tmp/screenmirror_audio.sock"
    private var fd: Int32 = -1

    init() {
        connect()
    }

    deinit {
        disconnect()
    }

    func connect() {
        guard fd == -1 else { return }

        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Self.socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(socketFD)
            return
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                _ = pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dest, src.baseAddress!, src.count)
                }
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let status = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(socketFD, sa, size)
            }
        }

        if status == 0 {
            fd = socketFD
        } else {
            close(socketFD)
        }
    }

    func disconnect() {
        if fd >= 0 {
            close(fd)
            fd = -1
        }
    }
}
