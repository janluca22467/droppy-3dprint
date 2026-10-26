import Foundation
import Network

@MainActor
final class BambuCameraFeed: CameraFeed {
    var onFrame: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    private let host: String
    private let accessCode: String
    private let port: UInt16 = 6000
    private var connection: NWConnection?
    private var buffer = Data()
    private var generation = 0
    private var running = false
    private var retryTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var lastFrame = Date.distantPast

    private static let headerSize = 16
    private static let maxFrameSize = 8_000_000

    init(host: String, accessCode: String) {
        self.host = host
        self.accessCode = accessCode
    }

    func start() {
        stop()
        running = true
        open()
    }

    func stop() {
        running = false
        generation += 1
        retryTask?.cancel(); retryTask = nil
        watchdogTask?.cancel(); watchdogTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    private func open() {
        generation += 1
        let gen = generation
        buffer.removeAll()
        lastFrame = Date()

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, .main)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 8
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: NWParameters(tls: tls, tcp: tcp))
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen else { return }
                switch state {
                case .ready:
                    connection.send(content: self.authPacket(), completion: .contentProcessed { _ in })
                    self.receive(on: connection, gen: gen)
                case .failed, .waiting:
                    self.fail()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)

        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.generation == gen else { return }
                if Date().timeIntervalSince(self.lastFrame) > 15 {
                    self.fail()
                    return
                }
            }
        }
    }

    private func authPacket() -> Data {
        var data = Data()
        data.appendLE(UInt32(0x40))
        data.appendLE(UInt32(0x3000))
        data.appendLE(UInt32(0))
        data.appendLE(UInt32(0))
        data.append(Self.padded("bblp"))
        data.append(Self.padded(accessCode))
        return data
    }

    private static func padded(_ string: String) -> Data {
        var bytes = Data(string.utf8.prefix(32))
        bytes.append(Data(count: 32 - bytes.count))
        return bytes
    }

    private func receive(on connection: NWConnection, gen: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.drain()
                }
                if error != nil || complete {
                    self.fail()
                } else {
                    self.receive(on: connection, gen: gen)
                }
            }
        }
    }

    private func drain() {
        while buffer.count >= Self.headerSize {
            let s = buffer.startIndex
            let size = Int(buffer[s]) | Int(buffer[s + 1]) << 8 | Int(buffer[s + 2]) << 16 | Int(buffer[s + 3]) << 24
            guard size > 0, size <= Self.maxFrameSize else {
                fail()
                return
            }
            guard buffer.count >= Self.headerSize + size else { return }
            let frame = buffer.subdata(in: (s + Self.headerSize)..<(s + Self.headerSize + size))
            buffer.removeSubrange(s..<(s + Self.headerSize + size))
            if frame.count > 4, frame[frame.startIndex] == 0xFF, frame[frame.startIndex + 1] == 0xD8 {
                lastFrame = Date()
                onFrame?(frame)
            }
        }
    }

    private func fail() {
        guard running else { return }
        generation += 1
        watchdogTask?.cancel(); watchdogTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll()
        onError?(L.s("cam.unavailable"))
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled, self.running else { return }
            self.open()
        }
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
