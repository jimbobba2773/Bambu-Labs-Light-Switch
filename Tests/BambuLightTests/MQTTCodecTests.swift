import XCTest
@testable import BambuLight

final class MQTTCodecTests: XCTestCase {
    func testRemainingLengthEncoding() {
        XCTAssertEqual(Array(MQTTCodec.packet(0x30, Data(count: 0)).prefix(2)), [0x30, 0x00])
        XCTAssertEqual(Array(MQTTCodec.packet(0x30, Data(count: 127)).prefix(2)), [0x30, 0x7F])
        XCTAssertEqual(Array(MQTTCodec.packet(0x30, Data(count: 128)).prefix(3)), [0x30, 0x80, 0x01])
        XCTAssertEqual(Array(MQTTCodec.packet(0x30, Data(count: 16384)).prefix(4)), [0x30, 0x80, 0x80, 0x01])
    }

    func testPublishRoundTrip() throws {
        let payload = Data(#"{"print":{"mc_percent":42}}"#.utf8)
        let bytes = MQTTCodec.publish(topic: "device/ABC/request", payload: payload)
        guard case .packet(let type, let body, let used) = MQTTCodec.nextFrame(bytes) else { return XCTFail("expected a packet") }
        XCTAssertEqual(used, bytes.count)
        let m = try XCTUnwrap(MQTTCodec.parsePublish(type: type, body: body))
        XCTAssertEqual(m.topic, "device/ABC/request")
        XCTAssertEqual(m.payload, payload)
    }

    func testLargePayloadRoundTrip() throws {
        let payload = Data((0..<20_000).map { UInt8($0 % 251) })
        let bytes = MQTTCodec.publish(topic: "t", payload: payload)
        guard case .packet(let type, let body, _) = MQTTCodec.nextFrame(bytes) else { return XCTFail() }
        XCTAssertEqual(MQTTCodec.parsePublish(type: type, body: body)?.payload, payload)
    }

    func testEveryTruncatedPrefixIsIncomplete() {
        let bytes = MQTTCodec.publish(topic: "device/ABC/report", payload: Data(repeating: 1, count: 300))
        for n in 0..<bytes.count {
            XCTAssertEqual(MQTTCodec.nextFrame(bytes.prefix(n)), .incomplete, "prefix \(n)")
        }
    }

    func testTwoPacketsBackToBack() {
        let a = MQTTCodec.publish(topic: "a", payload: Data([1, 2, 3]))
        let b = MQTTCodec.publish(topic: "b", payload: Data([4]))
        guard case .packet(_, _, let used) = MQTTCodec.nextFrame(a + b) else { return XCTFail() }
        XCTAssertEqual(used, a.count)
    }

    func testBufferThatIsASliceWithNonZeroStartIndex() {
        let a = MQTTCodec.publish(topic: "a", payload: Data([1]))
        let b = MQTTCodec.publish(topic: "bb", payload: Data([2, 3]))
        var buffer = a + b
        buffer.removeFirst(a.count)
        XCTAssertEqual(MQTTCodec.nextFrame(buffer), .packet(type: 0x30, body: buffer.dropFirst(2).asData, used: b.count))
    }

    func testOverlongRemainingLengthIsMalformed() {
        XCTAssertEqual(MQTTCodec.nextFrame(Data([0x30, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])), .malformed)
    }

    func testQoS1PublishSkipsPacketId() throws {
        // type 0x32 = PUBLISH with QoS 1; the 2 bytes after the topic are the packet id
        let body = MQTTCodec.str("t") + Data([0x00, 0x07]) + Data("hi".utf8)
        let m = try XCTUnwrap(MQTTCodec.parsePublish(type: 0x32, body: body))
        XCTAssertEqual(m.topic, "t")
        XCTAssertEqual(String(decoding: m.payload, as: UTF8.self), "hi")
    }

    func testPublishWithTruncatedTopicIsRejected() {
        XCTAssertNil(MQTTCodec.parsePublish(type: 0x30, body: Data([0x00, 0x09, 0x61])))
        XCTAssertNil(MQTTCodec.parsePublish(type: 0x30, body: Data([0x00])))
    }

    func testConnectAndSubscribeHeaders() {
        let c = MQTTCodec.connect(user: "bblp", pass: "secret", clientId: "x")
        XCTAssertEqual(c.first, 0x10)
        XCTAssertNotNil(c.range(of: Data("MQTT".utf8)))
        XCTAssertNotNil(c.range(of: Data("bblp".utf8)))
        let s = MQTTCodec.subscribe(packetId: 1, topics: ["device/ABC/report"])
        XCTAssertEqual(s.first, 0x82)
        XCTAssertEqual(Array(s.dropFirst(2).prefix(2)), [0x00, 0x01])
    }
}

private extension Data.SubSequence {
    var asData: Data { Data(self) }
}
