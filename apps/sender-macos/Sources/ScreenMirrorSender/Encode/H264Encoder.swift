import CoreMedia
import Foundation
import VideoToolbox

/// Codifica H.264 en hardware (VideoToolbox) y emite **Annex-B** listo para `POST /stream`.
///
/// El receptor exige: 4:2:0 (lo da el pipeline, entramos en BGRA), sin B-frames,
/// keyframe cada 2 s y SPS/PPS inline antes de cada IDR.
final class H264Encoder {
    private enum AnnexB {
        static let startCode = Data([0x00, 0x00, 0x00, 0x01])
    }

    private let config: StreamConfig
    private var session: VTCompressionSession?
    private var sps: Data?
    private var pps: Data?
    private var nalUnitHeaderLength = 4
    private var forceKeyFrame = true

    var onAccessUnit: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    init(config: StreamConfig) throws {
        self.config = config

        var compressionSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.width),
            height: Int32(config.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { refcon, _, encodeStatus, _, sampleBuffer in
                guard let refcon else { return }
                let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
                encoder.handle(encodeStatus: encodeStatus, sampleBuffer: sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession,
        )
        guard status == noErr, let compressionSession else {
            throw SenderError.encoderFailed("VTCompressionSessionCreate \(status)")
        }
        session = compressionSession

        try configure(compressionSession)
        VTCompressionSessionPrepareToEncodeFrames(compressionSession)
    }

    /// Convierte un frame de la captura en un access unit Annex-B.
    func encode(_ pixelBuffer: CVPixelBuffer, at presentationTime: CMTime) {
        guard let session else { return }

        var frameProperties: CFDictionary?
        if forceKeyFrame {
            forceKeyFrame = false
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil,
        )
        if status != noErr {
            onError?(SenderError.encoderFailed("EncodeFrame \(status)"))
        }
    }

    func finish() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    // MARK: - Configuración

    private func configure(_ session: VTCompressionSession) throws {
        let bitrate = config.bitrateKbps * 1000
        let properties: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, config.keyint as CFNumber),
            (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 2.0 as CFNumber),
            (kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber),
            (kVTCompressionPropertyKey_ExpectedFrameRate, config.fps as CFNumber),
        ]
        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value)
            // Algún encoder hardware ignora propiedades concretas: solo fallamos si es grave.
            if status != noErr, key == kVTCompressionPropertyKey_RealTime {
                throw SenderError.encoderFailed("RealTime \(status)")
            }
        }
    }

    // MARK: - Salida

    private func handle(encodeStatus: OSStatus, sampleBuffer: CMSampleBuffer?) {
        guard encodeStatus == noErr else {
            onError?(SenderError.encoderFailed("callback \(encodeStatus)"))
            return
        }
        guard let sampleBuffer else { return }
        do {
            onAccessUnit?(try accessUnit(from: sampleBuffer))
        } catch {
            onError?(error)
        }
    }

    private func accessUnit(from sampleBuffer: CMSampleBuffer) throws -> Data {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw SenderError.encoderFailed("frame sin buffer")
        }

        let isKeyFrame = Self.isKeyFrame(sampleBuffer)
        if isKeyFrame {
            // El receptor pide SPS/PPS inline antes de cada IDR: así puede entrar
            // a mitad de stream y reconectar sin esperar al siguiente keyframe.
            try cacheParameterSets(from: sampleBuffer)
        }

        var accessUnit = Data()
        if isKeyFrame, let sps, let pps {
            accessUnit.append(AnnexB.startCode)
            accessUnit.append(sps)
            accessUnit.append(AnnexB.startCode)
            accessUnit.append(pps)
        }
        accessUnit.append(try Self.annexBData(from: dataBuffer, headerLength: nalUnitHeaderLength))
        return accessUnit
    }

    private func cacheParameterSets(from sampleBuffer: CMSampleBuffer) throws {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw SenderError.encoderFailed("frame sin format description")
        }
        sps = try parameterSet(at: 0, in: formatDescription)
        pps = try parameterSet(at: 1, in: formatDescription)
    }

    private func parameterSet(at index: Int, in formatDescription: CMFormatDescription) throws -> Data {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        var headerLength: Int32 = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: index,
            parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: &headerLength,
        )
        guard status == noErr, let pointer, size > 0 else {
            throw SenderError.encoderFailed("parameterSet \(index) \(status)")
        }
        if headerLength > 0 { nalUnitHeaderLength = Int(headerLength) }
        return Data(bytes: pointer, count: size)
    }

    private static func isKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false,
            ) as? [[CFString: Any]],
            let first = attachments.first
        else { return true }
        return (first[kCMSampleAttachmentKey_NotSync] as? Bool) != true
    }

    /// Convierte el buffer AVCC (longitud de 4 bytes delante de cada NALU) a Annex-B (start codes).
    private static func annexBData(from blockBuffer: CMBlockBuffer, headerLength: Int) throws -> Data {
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return Data() }

        var raw = Data(count: length)
        try raw.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            guard let baseAddress = destination.baseAddress else {
                throw SenderError.encoderFailed("sin memoria para el frame")
            }
            let status = CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: length,
                destination: baseAddress,
            )
            guard status == noErr else {
                throw SenderError.encoderFailed("CMBlockBufferCopyDataBytes \(status)")
            }
        }

        var annexB = Data()
        annexB.reserveCapacity(length + 16)
        var offset = 0
        while offset + headerLength <= length {
            var naluLength = 0
            for index in 0..<headerLength {
                naluLength = (naluLength << 8) | Int(raw[offset + index])
            }
            offset += headerLength
            guard naluLength > 0, offset + naluLength <= length else { break }
            annexB.append(AnnexB.startCode)
            annexB.append(raw.subdata(in: offset..<(offset + naluLength)))
            offset += naluLength
        }
        return annexB
    }
}
