import Foundation
import Network

final class MQTTClient: @unchecked Sendable {
    enum Event: Sendable {
        case connected
        case message(topic: String, payload: Data)
        case disconnected(String)
    }

    private let host: String
    private let port: UInt16
    private let clientID: String
    private let username: String?
    private let password: String?
    private let queue = DispatchQueue(label: "print-live.mqtt")
    private var connection: NWConnection?
    private var buffer = Data()
    private var pingTimer: DispatchSourceTimer?
    private var nextPacketID: UInt16 = 1
    private var onEvent: (@Sendable (Event) -> Void)?
    private var isOpen = false

    init(host: String, port: UInt16, clientID: String, username: String?, password: String?) {
        self.host = host
        self.port = port
        self.clientID = clientID
        self.username = username
        self.password = password
    }

    func connect(_ onEvent: @escaping @Sendable (Event) -> Void) {
        queue.async { [self] in
            self.onEvent = onEvent
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = 8
            let params = NWParameters(tls: tls, tcp: tcp)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.send(self.connectPacket())
                    self.receive()
                case .failed(let error):
                    self.close("\(error.localizedDescription)")
                case .waiting(let error):
                    self.close("\(error.localizedDescription)")
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func disconnect() {
        queue.async { [self] in
            if self.isOpen { self.send(Data([0xE0, 0x00])) }
            self.onEvent = nil
            self.teardown()
        }
    }

    func subscribe(_ topic: String) {
        queue.async { [self] in
            var body = Data()
            body.append(uint16: self.takePacketID())
            body.append(mqttString: topic)
            body.append(0)
            self.send(Self.packet(0x82, body))
        }
    }

    func publish(_ topic: String, _ payload: Data) {
        queue.async { [self] in
            var body = Data()
            body.append(mqttString: topic)
            body.append(payload)
            self.send(Self.packet(0x30, body))
        }
    }

    private func connectPacket() -> Data {
        var flags: UInt8 = 0x02
        if username != nil { flags |= 0x80 }
        if password != nil { flags |= 0x40 }
        var body = Data()
        body.append(mqttString: "MQTT")
        body.append(4)
        body.append(flags)
        body.append(uint16: 60)
        body.append(mqttString: clientID)
        if let username { body.append(mqttString: username) }
        if let password { body.append(mqttString: password) }
        return Self.packet(0x10, body)
    }

    private func takePacketID() -> UInt16 {
        defer { nextPacketID = nextPacketID == .max ? 1 : nextPacketID + 1 }
        return nextPacketID
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            if let error {
                self.close(error.localizedDescription)
            } else if complete {
                self.close("closed")
            } else {
                self.receive()
            }
        }
    }

    private func drain() {
        while let (type, flags, body, used) = Self.nextPacket(buffer) {
            buffer.removeFirst(used)
            handle(type: type, flags: flags, body: body)
        }
    }

    private func handle(type: UInt8, flags: UInt8, body: Data) {
        switch type {
        case 2:
            let code = body.count >= 2 ? body[body.startIndex + 1] : 255
            if code == 0 {
                isOpen = true
                startPing()
                onEvent?(.connected)
            } else {
                close("refused (\(code))")
            }
        case 3:
            guard body.count >= 2 else { return }
            let s = body.startIndex
            let topicLength = Int(body[s]) << 8 | Int(body[s + 1])
            var offset = s + 2 + topicLength
            guard offset <= body.endIndex else { return }
            let topic = String(decoding: body[(s + 2)..<offset], as: UTF8.self)
            let qos = (flags >> 1) & 0x03
            if qos > 0 {
                guard offset + 2 <= body.endIndex else { return }
                let id = body[offset..<(offset + 2)]
                offset += 2
                send(Self.packet(qos == 1 ? 0x40 : 0x50, Data(id)))
            }
            onEvent?(.message(topic: topic, payload: Data(body[offset...])))
        default:
            break
        }
    }

    private func startPing() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in self?.send(Data([0xC0, 0x00])) }
        timer.resume()
        pingTimer = timer
    }

    private func close(_ reason: String) {
        let handler = onEvent
        onEvent = nil
        teardown()
        handler?(.disconnected(reason))
    }

    private func teardown() {
        isOpen = false
        pingTimer?.cancel()
        pingTimer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    private static func packet(_ header: UInt8, _ body: Data) -> Data {
        var out = Data([header])
        var length = body.count
        repeat {
            var byte = UInt8(length % 128)
            length /= 128
            if length > 0 { byte |= 0x80 }
            out.append(byte)
        } while length > 0
        out.append(body)
        return out
    }

    private static func nextPacket(_ data: Data) -> (UInt8, UInt8, Data, Int)? {
        guard data.count >= 2 else { return nil }
        let s = data.startIndex
        var multiplier = 1
        var length = 0
        var index = s + 1
        while true {
            guard index < data.endIndex else { return nil }
            let byte = Int(data[index])
            length += (byte & 0x7F) * multiplier
            index += 1
            if byte & 0x80 == 0 { break }
            multiplier *= 128
            if multiplier > 128 * 128 * 128 { return nil }
        }
        guard index + length <= data.endIndex else { return nil }
        let header = data[s]
        return (header >> 4, header & 0x0F, Data(data[index..<(index + length)]), index + length - s)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    mutating func append(mqttString string: String) {
        let bytes = Data(string.utf8)
        append(uint16: UInt16(bytes.count))
        append(bytes)
    }
}
