import Foundation
import Network
import AppKit

/// P1/A1-series live view: JPEG frames over TLS on port 6000 (needs "LAN mode liveview" enabled on the printer).
enum CameraProtocol {
    static let port: UInt16 = 6000
    static let headerSize = 16
    static let maxFrameSize = 8 * 1024 * 1024

    /// 80-byte login packet: 0x40, 0x3000, 0, 0, then username and access code in 32-byte zero-padded fields.
    static func authPacket(user: String, accessCode: String) -> Data {
        func le(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } }
        func field(_ s: String) -> [UInt8] { Array((Array(s.utf8) + Array(repeating: 0, count: 32)).prefix(32)) }
        return Data(le(0x40) + le(0x3000) + le(0) + le(0) + field(user) + field(accessCode))
    }
}

/// Splits the camera byte stream into JPEG frames. Each frame is a 16-byte header (payload size as little-endian UInt32 first) plus the JPEG.
struct CameraFrameParser {
    private var buffer = [UInt8]()

    /// Feeds bytes; returns every complete JPEG and whether the stream is corrupt (bad size or not a JPEG).
    mutating func append(_ data: Data) -> (frames: [Data], malformed: Bool) {
        buffer.append(contentsOf: data)
        var frames: [Data] = []
        while buffer.count >= CameraProtocol.headerSize {
            let size = Int(buffer[0]) | Int(buffer[1]) << 8 | Int(buffer[2]) << 16 | Int(buffer[3]) << 24
            guard size >= 4, size <= CameraProtocol.maxFrameSize else { buffer.removeAll(); return (frames, true) }
            let total = CameraProtocol.headerSize + size
            guard buffer.count >= total else { break }
            let jpeg = Array(buffer[CameraProtocol.headerSize..<total])
            guard jpeg[0] == 0xFF, jpeg[1] == 0xD8 else { buffer.removeAll(); return (frames, true) }
            frames.append(Data(jpeg))
            buffer.removeFirst(total)
        }
        return (frames, false)
    }
}

final class CameraClient {
    var onFrame: ((Data) -> Void)?
    var onState: ((String) -> Void)?

    private let queue = DispatchQueue(label: "camera")
    private var conn: NWConnection?
    private var parser = CameraFrameParser()
    private var pinFailed = false

    func start(host: String, accessCode: String, pin: @escaping (String) -> Bool) {
        queue.async {
            self.doStop()
            self.parser = CameraFrameParser()
            self.pinFailed = false
            let tls = TLSSupport.selfSigned(queue: self.queue, pin: pin) { [weak self] in self?.pinFailed = true }
            let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: CameraProtocol.port)!, using: NWParameters(tls: tls))
            self.conn = c
            c.stateUpdateHandler = { [weak self, weak c] state in
                guard let self, let c, c === self.conn else { return }
                switch state {
                case .ready:
                    c.send(content: CameraProtocol.authPacket(user: "bblp", accessCode: accessCode), completion: .contentProcessed { _ in })
                    self.receive(c)
                case .failed(let e):
                    self.onState?(self.pinFailed ? "Certificate changed — printer identity doesn't match" : "Camera unavailable: \(e.localizedDescription)")
                case .waiting(let e): self.onState?("Camera unreachable: \(e.localizedDescription)")
                default: break
                }
            }
            c.start(queue: self.queue)
        }
    }

    func stop() { queue.async { self.doStop() } }

    private func doStop() {
        let c = conn; conn = nil
        c?.cancel()
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self, weak c] data, _, done, error in
            guard let self, let c, c === self.conn else { return }
            if let data {
                let r = self.parser.append(data)
                if let last = r.frames.last { self.onFrame?(last) }   // only the newest frame matters
                if r.malformed { self.doStop(); self.onState?("Camera stream error"); return }
            }
            if error != nil || done { self.doStop(); self.onState?("Camera disconnected"); return }
            self.receive(c)
        }
    }
}

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var message: String? = "Connecting to camera…"

    private let client = CameraClient()
    private var watchdog: Task<Void, Never>?

    init() {
        client.onFrame = { [weak self] data in
            guard let img = NSImage(data: data) else { return }
            Task { @MainActor in self?.image = img; self?.message = nil }
        }
        client.onState = { [weak self] s in
            Task { @MainActor in self?.message = s }
        }
    }

    func start(host: String, accessCode: String, serial: String) {
        image = nil
        message = "Connecting to camera…"
        client.start(host: host.trimmingCharacters(in: .whitespaces), accessCode: accessCode) { CertPins.check(serial, $0) }
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, let self, self.image == nil, self.message == "Connecting to camera…" else { return }
            self.message = "No video. Enable LAN mode liveview on the printer (Settings → General)."
        }
    }

    func stop() {
        watchdog?.cancel()
        client.stop()
    }
}
