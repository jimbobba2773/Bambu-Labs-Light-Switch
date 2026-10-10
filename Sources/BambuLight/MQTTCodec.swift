import Foundation

/// Pure MQTT 3.1.1 packet encoding/decoding (QoS 0 publishing, enough for Bambu), kept separate from the socket code so it can be tested.
enum MQTTCodec {
    enum Frame: Equatable {
        case packet(type: UInt8, body: Data, used: Int)
        case incomplete          // need more bytes
        case malformed           // protocol violation; the connection should be dropped
    }

    static func str(_ s: String) -> Data {
        let b = Data(s.utf8)
        return Data([UInt8(b.count >> 8), UInt8(b.count & 0xFF)]) + b
    }

    static func packet(_ header: UInt8, _ body: Data) -> Data {
        var out = Data([header])
        var n = body.count
        repeat {
            var byte = UInt8(n % 128); n /= 128
            if n > 0 { byte |= 0x80 }
            out.append(byte)
        } while n > 0
        return out + body
    }

    static func connect(user: String, pass: String, clientId: String) -> Data {
        var b = str("MQTT")
        b.append(contentsOf: [0x04, 0xC2, 0x00, 0x3C]) // v3.1.1, user+pass+clean, keepalive 60
        b.append(str(clientId))
        b.append(str(user)); b.append(str(pass))
        return packet(0x10, b)
    }

    static func subscribe(packetId: UInt16, topics: [String]) -> Data {
        var sub = Data([UInt8(packetId >> 8), UInt8(packetId & 0xFF)])
        for t in topics { sub.append(str(t)); sub.append(0) }
        return packet(0x82, sub)
    }

    static func publish(topic: String, payload: Data) -> Data {
        packet(0x30, str(topic) + payload)
    }

    /// Reads one packet from the front of `buffer` without consuming it.
    static func nextFrame(_ buffer: Data) -> Frame {
        guard buffer.count >= 2 else { return .incomplete }
        let base = buffer.startIndex
        var mult = 1, len = 0, i = 1
        while true {
            guard buffer.count > i else { return .incomplete }
            let byte = Int(buffer[base + i]); i += 1
            len += (byte & 0x7F) * mult; mult *= 128
            if byte & 0x80 == 0 { break }
            if i > 4 { return .malformed }   // remaining length is at most 4 bytes
        }
        guard buffer.count >= i + len else { return .incomplete }
        return .packet(type: buffer[base], body: Data(buffer[(base + i)..<(base + i + len)]), used: i + len)
    }

    /// Extracts topic and payload from a PUBLISH packet body (skipping the packet id for QoS > 0).
    static func parsePublish(type: UInt8, body: Data) -> (topic: String, payload: Data)? {
        guard body.count >= 2 else { return nil }
        let b = Array(body)
        let tlen = Int(b[0]) << 8 | Int(b[1])
        guard b.count >= 2 + tlen else { return nil }
        let topic = String(decoding: b[2..<(2 + tlen)], as: UTF8.self)
        var off = 2 + tlen
        if (type >> 1) & 0x3 > 0 { off += 2 }
        guard off <= b.count else { return nil }
        return (topic, Data(b[off...]))
    }
}
