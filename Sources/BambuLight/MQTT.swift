import Foundation
import Network
import CryptoKit
import Security

/// Minimal MQTT 3.1.1 client (QoS 0 only) over TLS — just enough for Bambu LAN mode.
final class MQTTClient {
    var onMessage: ((String, Data) -> Void)?
    var onState: ((String) -> Void)?

    private let queue = DispatchQueue(label: "mqtt")
    private var conn: NWConnection?
    private var buffer = Data()
    private var pingTimer: DispatchSourceTimer?
    private var subscriptions: [String] = []
    private var packetId: UInt16 = 0
    private var lastReceived = Date()
    private var pinFailed = false

    // All mutable state lives on `queue`; the public API just hops onto it.
    func connect(host: String, port: UInt16 = 8883, verifyCert: Bool = false, pin: ((String) -> Bool)? = nil, username: String, password: String, subscribe: [String]) {
        queue.async { self.doConnect(host: host, port: port, verifyCert: verifyCert, pin: pin, username: username, password: password, subscribe: subscribe) }
    }

    func disconnect() { queue.async { self.doDisconnect() } }

    func publish(topic: String, payload: Data) {
        queue.async {
            self.send(MQTTCodec.publish(topic: topic, payload: payload))
        }
    }

    private func doConnect(host: String, port: UInt16, verifyCert: Bool, pin: ((String) -> Bool)?, username: String, password: String, subscribe: [String]) {
        doDisconnect()
        subscriptions = subscribe
        lastReceived = Date()
        pinFailed = false

        let tls = NWProtocolTLS.Options()
        if !verifyCert {
            // Printers use a self-signed certificate, so chain validation is skipped (LAN only).
            // Instead the leaf certificate's SHA-256 is checked against a pinned value (trust on first use).
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] _, trust, done in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let pin,
                      let leaf = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate])?.first else { done(pin == nil); return }
                let fp = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
                let ok = pin(fp)
                if !ok { self?.pinFailed = true }
                done(ok)
            }, queue)
        }
        let params = NWParameters(tls: tls)
        let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        conn = c

        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, c === self.conn else { return }
            switch state {
            case .ready:
                self.send(self.connectPacket(user: username, pass: password))
                self.receive()
            case .failed(let e):
                self.onState?(self.pinFailed ? "Certificate changed — printer identity doesn't match"
                                             : "Connection failed: \(e.localizedDescription)")
            case .waiting(let e): self.onState?("Waiting: \(e.localizedDescription)")
            case .cancelled: break
            default: break
            }
        }
        onState?("Connecting…")
        c.start(queue: queue)
    }

    private func doDisconnect() {
        pingTimer?.cancel(); pingTimer = nil
        let c = conn; conn = nil
        c?.cancel()
        buffer.removeAll()
    }

    // MARK: Packets

    private func connectPacket(user: String, pass: String) -> Data {
        MQTTCodec.connect(user: user, pass: pass, clientId: "bambulight-\(UInt32.random(in: 0...UInt32.max))")
    }

    private func send(_ data: Data) {
        conn?.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: Receive

    private func receive() {
        guard let c = conn else { return }
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak c] data, _, done, error in
            guard let self, let c, c === self.conn else { return }
            if let data { self.lastReceived = Date(); self.buffer.append(data); self.drain() }
            if error != nil || done {
                self.onState?("Disconnected")
                return
            }
            self.receive()
        }
    }

    private func drain() {
        while true {
            switch MQTTCodec.nextFrame(buffer) {
            case .incomplete: return
            case .malformed:
                doDisconnect()
                onState?("Disconnected")
                return
            case .packet(let type, let body, let used):
                buffer.removeFirst(used)
                handle(type: type, body: body)
            }
        }
    }

    private func handle(type: UInt8, body: Data) {
        switch type >> 4 {
        case 2: // CONNACK
            if body.count >= 2 && body[body.startIndex + 1] == 0 {
                onState?("Connected")
                packetId &+= 1
                send(MQTTCodec.subscribe(packetId: packetId, topics: subscriptions))
                startPing()
            } else {
                onState?("Rejected — check credentials")
            }
        case 3: // PUBLISH
            if let m = MQTTCodec.parsePublish(type: type, body: body) { onMessage?(m.topic, m.payload) }
        default: break
        }
    }

    private func startPing() {
        pingTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            // Any inbound packet (incl. PINGRESP) refreshes lastReceived; silence means a dead socket.
            if Date().timeIntervalSince(self.lastReceived) > 90 {
                self.doDisconnect()
                self.onState?("Disconnected")
            } else {
                self.send(Data([0xC0, 0x00]))
            }
        }
        t.resume()
        pingTimer = t
    }
}
