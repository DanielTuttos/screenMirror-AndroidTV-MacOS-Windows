import AudioToolbox
import Foundation

/// Formato PCM real de la salida de audio del sistema.
///
/// El receptor solo acepta 44100/48000 Hz (spec: docs/protocol.md), así que le pasamos
/// `sr`/`ch` concretos en vez de asumir: si el sistema sonara a otra frecuencia, el
/// AudioTrack de la TV reproduciría a velocidad equivocada.
struct SystemAudioFormat: Equatable {
    let sampleRate: Int
    let channels: Int

    /// Devuelve el formato por defecto; ante cualquier fallo cae a 48 kHz estéreo
    /// (lo habitual en macOS) para no bloquear la emisión.
    static func current() -> SystemAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID,
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return SystemAudioFormat(sampleRate: 48_000, channels: 2)
        }

        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        var rate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        let rateStatus = AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &rateSize, &rate)
        guard rateStatus == noErr, rate > 0 else {
            return SystemAudioFormat(sampleRate: 48_000, channels: 2)
        }

        return SystemAudioFormat(sampleRate: Int(rate.rounded()), channels: channelCount(of: deviceID))
    }

    /// Canales del búfer de salida (salida estéreo → 2; un dispositivo mono → 1).
    private static func channelCount(of deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 2
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else {
            return 2
        }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        var channels = 0
        withUnsafePointer(to: list.pointee.mBuffers) { buffers in
            for index in 0..<Int(list.pointee.mNumberBuffers) {
                channels += Int(buffers.advanced(by: index).pointee.mNumberChannels)
            }
        }
        return max(1, channels)
    }
}
