import AudioToolbox
import CoreAudio
import Foundation

/// Captura el audio que se envía al dispositivo virtual **«ScreenMirror TV»** con un tap de
/// Core Audio (macOS 14.2+) y lo entrega como PCM s16le listo para `POST /audio`.
///
/// La persona decide a mano dónde suena cada cosa desde el control de sonido del Mac: lo que
/// manda a «ScreenMirror TV» va a la TV y el resto sigue en su salida de siempre. Este tap
/// es solo de lectura: no silencia ni redirige nada. El dispositivo lo aporta el driver de
/// `drivers/macos-audio`, que hay que instalar una vez.
final class SystemAudioTap {
    struct Format: Equatable {
        let sampleRate: Int
        let channels: Int
    }

    /// Debe coincidir con `kDeviceUID` en `drivers/macos-audio/Driver.cpp`.
    static let screenMirrorDeviceUID = "tv.screenmirror.audio.device"

    /// Frecuencias que acepta el receptor (docs/protocol.md).
    private static let supportedSampleRates = [44_100, 48_000]

    let format: Format
    /// Se llama en una cola propia (no en el hilo de tiempo real de Core Audio).
    var onPCM: ((Data) -> Void)?

    private let tapID: AudioObjectID
    private let aggregateID: AudioObjectID
    private let tapFormat: AudioStreamBasicDescription
    private let converter = PCMAudioConverter()
    private let queue = DispatchQueue(label: "tv.screenmirror.sender.audio", qos: .userInteractive)
    private var procID: AudioDeviceIOProcID?
    private var isRunning = false
    private var isReleased = false

    /// true si el driver «ScreenMirror TV» está instalado y coreaudiod lo ve.
    static func isDeviceInstalled() -> Bool {
        deviceID(forUID: screenMirrorDeviceUID) != nil
    }

    /// Crea el tap sobre el dispositivo «ScreenMirror TV»; no entrega audio hasta `start()`.
    init() throws {
        guard Self.isDeviceInstalled() else {
            throw SenderError.audioUnavailable(
                "falta el driver «ScreenMirror TV» (instálalo con drivers/macos-audio/install.sh)",
            )
        }
        let description = CATapDescription(
            __excludingProcesses: [],
            andDeviceUID: Self.screenMirrorDeviceUID,
            withStream: 0,
        )
        description.name = "ScreenMirror"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &tap), "crear el tap de audio")

        do {
            let asbd = try Self.tapFormat(of: tap)
            guard Self.supportedSampleRates.contains(Int(asbd.mSampleRate)) else {
                throw SenderError.audioUnavailable("frecuencia de \(Int(asbd.mSampleRate)) Hz no soportada")
            }
            tapFormat = asbd
            format = Format(sampleRate: Int(asbd.mSampleRate), channels: Int(asbd.mChannelsPerFrame))
            aggregateID = try Self.makeAggregateDevice(tapUUID: description.uuid)
            tapID = tap
        } catch {
            AudioHardwareDestroyProcessTap(tap)
            throw error
        }
    }

    deinit { stop() }

    func start() throws {
        guard !isRunning else { return }
        let tapFormat = tapFormat
        try Self.check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
                guard let self, let pcm = self.converter.convert(
                    bufferList: UnsafeMutablePointer(mutating: input),
                    format: tapFormat,
                ) else { return }
                self.onPCM?(pcm)
            },
            "crear el procesador de audio",
        )
        guard let procID else { throw SenderError.audioUnavailable("no se creó el procesador de audio") }
        try Self.check(AudioDeviceStart(aggregateID, procID), "arrancar la captura de audio")
        isRunning = true
    }

    /// Detiene la captura y libera el tap: el Mac vuelve a sonar.
    func stop() {
        guard !isReleased else { return }
        isReleased = true
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        AudioHardwareDestroyAggregateDevice(aggregateID)
        AudioHardwareDestroyProcessTap(tapID)
    }

    // MARK: - Privado

    private static func tapFormat(of tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd), "leer el formato del tap")
        return asbd
    }

    /// El tap solo entrega audio colgado de un dispositivo agregado; «ScreenMirror TV» le da el reloj.
    private static func makeAggregateDevice(tapUUID: UUID) throws -> AudioObjectID {
        let outputUID = screenMirrorDeviceUID
        let dictionary: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ScreenMirror Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(dictionary as CFDictionary, &aggregate), "crear el dispositivo de audio")
        return aggregate
    }

    /// Id del dispositivo con ese UID, o nil si coreaudiod no lo conoce (driver sin instalar).
    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        var cfUID = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &size,
                &device,
            )
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else {
            throw SenderError.audioUnavailable("no se pudo \(action) (OSStatus \(status))")
        }
    }
}
