import CommonCrypto
import CryptoKit
import Foundation

@MainActor
final class AnycubicConnection: PrinterConnection {
    var onStatus: ((PrintStatus) -> Void)?
    private let config: PrinterConfig
    private var client: MQTTClient?
    private var pollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var stopped = true
    private var modelID = ""
    private var deviceID = ""
    private var current = PrintStatus()

    private struct Credentials {
        let host: String
        let port: UInt16
        let username: String
        let password: String
        let deviceID: String
        let modelID: String
    }

    private enum HandshakeError: Error { case unreachable, cloudMode, badResponse }

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        return URLSession(configuration: c)
    }()

    init(config: PrinterConfig) { self.config = config }

    private var host: String {
        var h = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["http://", "https://"] where h.hasPrefix(prefix) { h.removeFirst(prefix.count) }
        return h.split(separator: "/").first.map(String.init)?.split(separator: ":").first.map(String.init) ?? h
    }

    func start() {
        stop()
        stopped = false
        current = PrintStatus(state: .connecting)
        onStatus?(current)
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                let creds = try await self.handshake()
                guard !Task.isCancelled, !self.stopped else { return }
                self.connect(creds)
            } catch HandshakeError.cloudMode {
                self.fail(L.s("err.lanMode"))
            } catch {
                self.fail(L.s("err.unreachable"))
            }
        }
    }

    func stop() {
        stopped = true
        startTask?.cancel(); startTask = nil
        pollTask?.cancel(); pollTask = nil
        retryTask?.cancel(); retryTask = nil
        client?.disconnect()
        client = nil
    }

    private func fail(_ message: String) {
        client = nil
        pollTask?.cancel()
        onStatus?(PrintStatus(state: .offline, message: message))
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled, !self.stopped else { return }
            self.start()
        }
    }

    private func handshake() async throws -> Credentials {
        guard let infoURL = URL(string: "http://\(host):18910/info"),
              let (infoData, _) = try? await session.data(from: infoURL),
              let info = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any] else { throw HandshakeError.unreachable }
        if (info["ctrlType"] as? String)?.lowercased() == "cloud" { throw HandshakeError.cloudMode }
        guard let token = info["token"] as? String, token.count >= 32 else { throw HandshakeError.badResponse }
        let model = (info["modelId"] as? String) ?? (info["modelId"] as? Int).map(String.init) ?? ""
        let ctrlURLString = (info["ctrlInfoUrl"] as? String) ?? "http://\(host):18910/ctrl"

        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let nonce = Self.random(6, from: "abcdefghijklmnopqrstuvwxyz0123456789")
        let did = Self.random(32, from: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let inner = Self.md5(String(token.prefix(16)))
        let sign = Self.md5(inner + String(ts) + nonce)

        guard var components = URLComponents(string: ctrlURLString) else { throw HandshakeError.badResponse }
        components.queryItems = [
            URLQueryItem(name: "ts", value: String(ts)),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "did", value: did),
        ]
        guard let ctrlURL = components.url else { throw HandshakeError.badResponse }
        var request = URLRequest(url: ctrlURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (ctrlData, _) = try? await session.data(for: request),
              let ctrl = try? JSONSerialization.jsonObject(with: ctrlData) as? [String: Any],
              (ctrl["code"] as? Int) == 200,
              let data = ctrl["data"] as? [String: Any],
              let localToken = data["token"] as? String,
              let cipherText = (data["info"] as? String).flatMap({ Data(base64Encoded: $0) }) else { throw HandshakeError.badResponse }

        let key = Data(token.utf8)[16..<32]
        var iv = Data(localToken.utf8.prefix(16))
        if iv.count < 16 { iv.append(Data(count: 16 - iv.count)) }
        guard let plain = Self.aesDecrypt(cipherText, key: Data(key), iv: iv),
              let payload = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let broker = payload["broker"] as? String,
              let username = payload["username"] as? String,
              let password = payload["password"] as? String,
              let deviceID = payload["deviceId"] as? String else { throw HandshakeError.badResponse }

        var brokerHost = host
        var brokerPort: UInt16 = 9883
        if let url = URL(string: broker) {
            if let h = url.host, !h.isEmpty { brokerHost = h }
            if let p = url.port, let port = UInt16(exactly: p) { brokerPort = port }
        }
        return Credentials(host: brokerHost, port: brokerPort, username: username, password: password, deviceID: deviceID, modelID: model)
    }

    private func connect(_ creds: Credentials) {
        modelID = creds.modelID
        deviceID = creds.deviceID
        let client = MQTTClient(
            host: creds.host,
            port: creds.port,
            clientID: "print-live-\(UUID().uuidString.prefix(8).lowercased())",
            username: creds.username,
            password: creds.password
        )
        self.client = client
        client.connect { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    private func handle(_ event: MQTTClient.Event) {
        guard !stopped else { return }
        switch event {
        case .connected:
            client?.subscribe("anycubic/anycubicCloud/v1/printer/public/\(modelID)/\(deviceID)/#")
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.query()
                    let active = self?.current.state.isActive ?? false
                    try? await Task.sleep(nanoseconds: active ? 5_000_000_000 : 15_000_000_000)
                }
            }
        case .message(let topic, let payload):
            guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let data = json["data"] as? [String: Any] else { return }
            apply(topic: topic, data: data)
        case .disconnected(let reason):
            fail(reason.contains("refused") ? L.s("err.refused") : L.s("err.unreachable"))
        }
    }

    private func query() {
        let base = "anycubic/anycubicCloud/v1"
        send("\(base)/web/printer/\(modelID)/\(deviceID)/info", type: "info")
        send("\(base)/web/printer/\(modelID)/\(deviceID)/tempature", type: "tempature")
        send("\(base)/slicer/printer/\(modelID)/\(deviceID)/print", type: "print")
    }

    private func send(_ topic: String, type: String) {
        let body: [String: Any] = [
            "type": type,
            "action": "query",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "msgid": UUID().uuidString.lowercased(),
            "data": NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.publish(topic, data)
    }

    private func apply(topic: String, data: [String: Any]) {
        var s = current
        if topic.hasSuffix("/info/report") {
            if let temp = data["temp"] as? [String: Any] { applyTemps(temp, to: &s) }
            if let project = data["project"] as? [String: Any] {
                applyProject(project, to: &s)
            } else if data.keys.contains("project") {
                let printer = (data["state"] as? String ?? "").lowercased()
                s.state = printer == "offline" ? .offline : .idle
                s.progress = nil; s.remaining = nil; s.layer = nil; s.totalLayers = nil; s.fileName = nil
            }
        } else if topic.hasSuffix("/tempature/report") {
            applyTemps(data, to: &s)
        } else if topic.hasSuffix("/print/report") {
            applyProject(data, to: &s)
        } else {
            return
        }
        s.message = nil
        s.updated = Date()
        current = s
        onStatus?(s)
    }

    private func applyTemps(_ t: [String: Any], to s: inout PrintStatus) {
        s.nozzle = number(t["curr_nozzle_temp"]) ?? s.nozzle
        s.nozzleTarget = number(t["target_nozzle_temp"]) ?? s.nozzleTarget
        s.bed = number(t["curr_hotbed_temp"]) ?? s.bed
        s.bedTarget = number(t["target_hotbed_temp"]) ?? s.bedTarget
    }

    private func applyProject(_ p: [String: Any], to s: inout PrintStatus) {
        switch (p["state"] as? String ?? "").lowercased() {
        case "free", "": s.state = .idle
        case "preheating", "auto_leveling", "vibrating", "flow_calibrating", "downloading", "checking": s.state = .preparing
        case "printing", "resuming", "resumed": s.state = .printing
        case "pausing", "paused": s.state = .paused
        case "stopping", "stoped", "stopped", "canceled": s.state = .stopped
        case "finished", "finish", "complete": s.state = .finished
        case "failed", "error": s.state = .failed
        default: s.state = .printing
        }
        switch number(p["pause"]).map(Int.init) {
        case 1, 2: s.state = .paused
        case 4: s.state = .stopped
        default: break
        }
        if let progress = number(p["progress"]) { s.progress = progress / 100 }
        if let remain = number(p["remain_time"]) { s.remaining = remain * 60 }
        if let printed = number(p["print_time"]) { s.elapsed = printed * 60 }
        s.layer = number(p["curr_layer"]).map(Int.init) ?? s.layer
        s.totalLayers = (number(p["total_layers"]) ?? number(p["total_layer"])).map(Int.init) ?? s.totalLayers
        s.fileName = (p["filename"] as? String).cleanedFileName ?? s.fileName
        if s.state == .finished { s.progress = 1; s.remaining = 0 }
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func random(_ count: Int, from alphabet: String) -> String {
        let chars = Array(alphabet)
        return String((0..<count).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private static func md5(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func aesDecrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        var moved = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                dataBytes.baseAddress, data.count, outBytes.baseAddress, outCapacity, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(moved)
    }
}
