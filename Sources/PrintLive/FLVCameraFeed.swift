import CoreImage
import CoreMedia
import Foundation
import ImageIO
import VideoToolbox

struct AVCConfig: Equatable, Sendable {
    var sps: [Data]
    var pps: [Data]
    var lengthSize: Int

    static func parse(_ record: Data) -> AVCConfig? {
        let b = [UInt8](record)
        guard b.count >= 7, b[0] == 1 else { return nil }
        let lengthSize = Int(b[4] & 0x03) + 1
        var i = 5
        var sps: [Data] = []
        var pps: [Data] = []
        let spsCount = Int(b[i] & 0x1F)
        i += 1
        for _ in 0..<spsCount {
            guard i + 2 <= b.count else { return nil }
            let len = Int(b[i]) << 8 | Int(b[i + 1])
            i += 2
            guard len > 0, i + len <= b.count else { return nil }
            sps.append(Data(b[i..<(i + len)]))
            i += len
        }
        guard i < b.count else { return nil }
        let ppsCount = Int(b[i])
        i += 1
        for _ in 0..<ppsCount {
            guard i + 2 <= b.count else { return nil }
            let len = Int(b[i]) << 8 | Int(b[i + 1])
            i += 2
            guard len > 0, i + len <= b.count else { return nil }
            pps.append(Data(b[i..<(i + len)]))
            i += len
        }
        guard !sps.isEmpty, !pps.isEmpty else { return nil }
        return AVCConfig(sps: sps, pps: pps, lengthSize: lengthSize)
    }

    static func nalUnits(_ data: Data, lengthSize: Int) -> [Data] {
        let b = [UInt8](data)
        var units: [Data] = []
        var i = 0
        while i + lengthSize <= b.count {
            var len = 0
            for k in 0..<lengthSize { len = len << 8 | Int(b[i + k]) }
            i += lengthSize
            guard len > 0, i + len <= b.count else { break }
            units.append(Data(b[i..<(i + len)]))
            i += len
        }
        return units
    }
}

enum FLVEvent: Equatable, Sendable {
    case config(AVCConfig)
    case video(Data, keyframe: Bool, timestamp: UInt32)
}

struct FLVDemuxer: Sendable {
    enum Failure: Error { case badHeader, oversized }

    private var buffer: [UInt8] = []
    private var headerDone = false
    private static let maxTag = 8_000_000

    mutating func reset() {
        buffer.removeAll()
        headerDone = false
    }

    mutating func feed(_ data: Data) throws -> [FLVEvent] {
        buffer.append(contentsOf: data)
        var events: [FLVEvent] = []
        var i = 0
        if !headerDone {
            guard buffer.count >= 9 else { return events }
            guard buffer[0] == 0x46, buffer[1] == 0x4C, buffer[2] == 0x56 else { throw Failure.badHeader }
            let offset = Int(buffer[5]) << 24 | Int(buffer[6]) << 16 | Int(buffer[7]) << 8 | Int(buffer[8])
            guard offset >= 9, offset < 1024 else { throw Failure.badHeader }
            guard buffer.count >= offset + 4 else { return events }
            i = offset + 4
            headerDone = true
        }
        while i + 11 <= buffer.count {
            let type = buffer[i] & 0x1F
            let size = Int(buffer[i + 1]) << 16 | Int(buffer[i + 2]) << 8 | Int(buffer[i + 3])
            guard size <= Self.maxTag else { throw Failure.oversized }
            guard i + 11 + size + 4 <= buffer.count else { break }
            let timestamp = UInt32(buffer[i + 7]) << 24 | UInt32(buffer[i + 4]) << 16 | UInt32(buffer[i + 5]) << 8 | UInt32(buffer[i + 6])
            let body = i + 11
            if type == 9, size >= 5, buffer[body] & 0x0F == 7 {
                let keyframe = buffer[body] >> 4 == 1
                let payload = Data(buffer[(body + 5)..<(body + size)])
                switch buffer[body + 1] {
                case 0:
                    if let config = AVCConfig.parse(payload) { events.append(.config(config)) }
                case 1:
                    if !payload.isEmpty { events.append(.video(payload, keyframe: keyframe, timestamp: timestamp)) }
                default:
                    break
                }
            }
            i = body + size + 4
        }
        if i > 0 { buffer.removeFirst(min(i, buffer.count)) }
        return events
    }
}

private final class FLVFrameEncoder: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "printlive.flv.jpeg", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    private let maxWidth: CGFloat = 960

    func encode(_ pixelBuffer: CVPixelBuffer, completion: @escaping @Sendable (Data) -> Void) {
        lock.lock()
        if busy { lock.unlock(); return }
        busy = true
        lock.unlock()
        let box = PixelBox(buffer: pixelBuffer)
        queue.async { [self] in
            defer { lock.lock(); busy = false; lock.unlock() }
            var image = CIImage(cvPixelBuffer: box.buffer)
            let width = image.extent.width
            if width > maxWidth {
                let scale = maxWidth / width
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let data = context.jpegRepresentation(of: image, colorSpace: space, options: [quality: 0.7]) else { return }
            completion(data)
        }
    }
}

private struct PixelBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

@MainActor
final class FLVCameraFeed: NSObject, CameraFeed, URLSessionDataDelegate {
    var onFrame: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    private let url: URL
    private var session: URLSession?
    private var demuxer = FLVDemuxer()
    private var config: AVCConfig?
    private var format: CMVideoFormatDescription?
    private var decoder: VTDecompressionSession?
    private var needsKeyframe = true
    private let encoder = FLVFrameEncoder()
    private var running = false
    private var generation = 0
    private var lastEmit = Date.distantPast
    private var lastData = Date.distantPast
    private var connectTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    func start() {
        stop()
        running = true
        schedule(after: 1)
    }

    func stop() {
        let wasRunning = running
        running = false
        generation += 1
        connectTask?.cancel(); connectTask = nil
        watchdogTask?.cancel(); watchdogTask = nil
        closeStream()
        if wasRunning { onStop?() }
    }

    private func schedule(after seconds: Double) {
        connectTask?.cancel()
        onStart?()
        connectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled, self.running else { return }
            self.open()
        }
    }

    private func open() {
        closeStream()
        generation += 1
        let gen = generation
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        lastData = Date()
        session.dataTask(with: URLRequest(url: url)).resume()
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.generation == gen, self.running else { return }
                if Date().timeIntervalSince(self.lastData) > 15 {
                    self.fail()
                    return
                }
            }
        }
    }

    private func closeStream() {
        session?.invalidateAndCancel()
        session = nil
        demuxer.reset()
        config = nil
        format = nil
        if let decoder { VTDecompressionSessionInvalidate(decoder) }
        decoder = nil
    }

    private func fail() {
        guard running else { return }
        watchdogTask?.cancel(); watchdogTask = nil
        closeStream()
        generation += 1
        onError?(L.s("cam.unavailable"))
        schedule(after: 5)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let ok = ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400
        completionHandler(ok ? .allow : .cancel)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            guard self.session === session else { return }
            self.consume(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard self.session === session else { return }
            self.fail()
        }
    }

    private func consume(_ data: Data) {
        lastData = Date()
        let events: [FLVEvent]
        do {
            events = try demuxer.feed(data)
        } catch {
            fail()
            return
        }
        for event in events {
            switch event {
            case .config(let config):
                apply(config)
            case .video(let payload, let keyframe, let timestamp):
                if config == nil, let inline = inlineConfig(payload) { apply(inline) }
                decode(payload, keyframe: keyframe, timestamp: timestamp)
            }
        }
    }

    private func inlineConfig(_ payload: Data) -> AVCConfig? {
        let units = AVCConfig.nalUnits(payload, lengthSize: 4)
        let sps = units.filter { ($0.first ?? 0) & 0x1F == 7 }
        let pps = units.filter { ($0.first ?? 0) & 0x1F == 8 }
        guard !sps.isEmpty, !pps.isEmpty else { return nil }
        return AVCConfig(sps: sps, pps: pps, lengthSize: 4)
    }

    private func apply(_ newConfig: AVCConfig) {
        guard newConfig != config || decoder == nil else { return }
        config = newConfig
        guard let description = Self.formatDescription(newConfig) else { return }
        if let decoder, VTDecompressionSessionCanAcceptFormatDescription(decoder, formatDescription: description) {
            format = description
            return
        }
        if let decoder { VTDecompressionSessionInvalidate(decoder) }
        decoder = nil
        format = description
        var created: VTDecompressionSession?
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        let status = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: description,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &created
        )
        if status == noErr {
            decoder = created
            needsKeyframe = true
        }
    }

    private static func formatDescription(_ config: AVCConfig) -> CMVideoFormatDescription? {
        let sets = config.sps + config.pps
        let buffers = sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers = buffers.map { UnsafePointer($0) }
        let sizes = sets.map(\.count)
        var description: CMVideoFormatDescription?
        let status = pointers.withUnsafeBufferPointer { p in
            sizes.withUnsafeBufferPointer { s in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: sets.count,
                    parameterSetPointers: p.baseAddress!,
                    parameterSetSizes: s.baseAddress!,
                    nalUnitHeaderLength: Int32(config.lengthSize),
                    formatDescriptionOut: &description
                )
            }
        }
        return status == noErr ? description : nil
    }

    private func decode(_ payload: Data, keyframe: Bool, timestamp: UInt32) {
        guard let decoder, let format else { return }
        if needsKeyframe {
            guard keyframe else { return }
            needsKeyframe = false
        }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: payload.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block
        ) == kCMBlockBufferNoErr, let block else { return }
        let copied = payload.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count)
        }
        guard copied == kCMBlockBufferNoErr else { return }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(timestamp), timescale: 1000),
            decodeTimeStamp: .invalid
        )
        var size = payload.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample
        ) == noErr, let sample else { return }

        let wanted = Date().timeIntervalSince(lastEmit) >= 0.2
        if wanted { lastEmit = Date() }
        let gen = generation
        let encoder = self.encoder
        let status = VTDecompressionSessionDecodeFrame(decoder, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { [weak self] status, _, imageBuffer, _, _ in
            guard wanted, status == noErr, let imageBuffer else { return }
            encoder.encode(imageBuffer) { data in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.generation == gen, self.running else { return }
                        self.onFrame?(data)
                    }
                }
            }
        }
        if status == kVTInvalidSessionErr {
            VTDecompressionSessionInvalidate(decoder)
            self.decoder = nil
            if let config { self.config = nil; apply(config) }
        }
    }
}
