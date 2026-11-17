import AudioToolbox
import Foundation

/// Convierte un `AudioBufferList` (Float32 o Int16, intercalado o no) a **PCM s16le
/// intercalado**, el formato que fija `docs/protocol.md` para `POST /audio`.
///
/// Es lo mínimo que entiende el `AudioTrack` del receptor sin añadir codificación.
final class PCMAudioConverter {

    /// Devuelve `nil` si el formato no es PCM o no hay muestras: el caller descarta (no se traga errores).
    func convert(bufferList list: UnsafeMutablePointer<AudioBufferList>, format asbd: AudioStreamBasicDescription) -> Data? {
        guard asbd.mFormatID == kAudioFormatLinearPCM else { return nil }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSigned = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isBigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        guard isFloat || (isSigned && asbd.mBitsPerChannel == 16) else { return nil }

        let channels = Int(asbd.mChannelsPerFrame)
        guard channels >= 1, asbd.mBytesPerFrame > 0 else { return nil }

        // Mono/estéreo suele ser 1 buffer intercalado; los desintercalados traen un buffer por canal.
        let bufferCount = Int(list.pointee.mNumberBuffers)
        guard bufferCount >= 1 else { return nil }

        let first = list.pointee.mBuffers
        guard let data = first.mData else { return nil }
        let frames = Int(first.mDataByteSize) / Int(asbd.mBytesPerFrame)
        guard frames > 0 else { return nil }

        var out = Data(capacity: frames * channels * 2)
        if bufferCount == 1, channels <= 2 {
            appendInterleaved(data, frames: frames, channels: channels, isFloat: isFloat, isBigEndian: isBigEndian, into: &out)
        } else {
            appendDeinterleaved(list, frames: frames, channels: channels, isFloat: isFloat, isBigEndian: isBigEndian, into: &out)
        }
        return out
    }

    // MARK: - Privado

    private func appendInterleaved(
        _ raw: UnsafeMutableRawPointer,
        frames: Int,
        channels: Int,
        isFloat: Bool,
        isBigEndian: Bool,
        into out: inout Data,
    ) {
        if isFloat {
            let samples = raw.bindMemory(to: Float.self, capacity: frames * channels)
            for i in 0..<(frames * channels) {
                append(sample(samples[i]), to: &out)
            }
        } else {
            let bytes = raw.bindMemory(to: UInt8.self, capacity: frames * channels * 2)
            for i in 0..<(frames * channels) {
                let offset = i * 2
                if isBigEndian {
                    out.append(bytes[offset + 1])
                    out.append(bytes[offset])
                } else {
                    out.append(bytes[offset])
                    out.append(bytes[offset + 1])
                }
            }
        }
    }

    private func appendDeinterleaved(
        _ list: UnsafeMutablePointer<AudioBufferList>,
        frames: Int,
        channels: Int,
        isFloat: Bool,
        isBigEndian: Bool,
        into out: inout Data,
    ) {
        var converted = [Int16](repeating: 0, count: frames * channels)
        let bufferCount = min(Int(list.pointee.mNumberBuffers), channels)
        // mBuffers es un array flexible de 1 elemento: hay que desplazar el puntero a mano.
        withUnsafeMutablePointer(to: &list.pointee.mBuffers) { buffers in
            for bufferIndex in 0..<bufferCount {
                let buffer = buffers.advanced(by: bufferIndex).pointee
                guard let data = buffer.mData else { continue }
                if isFloat {
                    let samples = data.bindMemory(to: Float.self, capacity: frames)
                    for frame in 0..<frames {
                        converted[frame * channels + bufferIndex] = sample(samples[frame])
                    }
                } else {
                    let bytes = data.bindMemory(to: UInt8.self, capacity: frames * 2)
                    for frame in 0..<frames {
                        let offset = frame * 2
                        let low = isBigEndian ? bytes[offset + 1] : bytes[offset]
                        let high = isBigEndian ? bytes[offset] : bytes[offset + 1]
                        converted[frame * channels + bufferIndex] = Int16(bitPattern: UInt16(low) | (UInt16(high) << 8))
                    }
                }
            }
        }
        converted.withUnsafeBufferPointer { pointer in
            out.append(Data(bytes: pointer.baseAddress!, count: pointer.count * 2))
        }
    }

    private func append(_ value: Int16, to out: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { out.append(contentsOf: $0) }
    }

    private func sample(_ value: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, value))
        let scaled = Int32((clamped * Float(Int16.max)).rounded())
        return Int16(clamping: scaled)
    }
}
