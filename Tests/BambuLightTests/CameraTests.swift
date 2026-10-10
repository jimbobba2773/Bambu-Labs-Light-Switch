import XCTest
@testable import BambuLight

final class CameraTests: XCTestCase {
    private func frame(_ jpeg: [UInt8]) -> Data {
        let n = UInt32(jpeg.count)
        let header = [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)] + [UInt8](repeating: 0, count: 12)
        return Data(header + jpeg)
    }
    private let jpegA: [UInt8] = [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]
    private let jpegB: [UInt8] = [0xFF, 0xD8, 9, 0xFF, 0xD9]

    func testAuthPacketLayout() {
        let p = Array(CameraProtocol.authPacket(user: "bblp", accessCode: "12345678"))
        XCTAssertEqual(p.count, 80)
        XCTAssertEqual(Array(p[0..<8]), [0x40, 0, 0, 0, 0x00, 0x30, 0, 0])
        XCTAssertEqual(Array(p[16..<20]), Array("bblp".utf8))
        XCTAssertEqual(p[20], 0)
        XCTAssertEqual(Array(p[48..<56]), Array("12345678".utf8))
        XCTAssertEqual(p[56], 0)
    }

    func testAuthPacketTruncatesLongFields() {
        let p = CameraProtocol.authPacket(user: String(repeating: "u", count: 50), accessCode: "x")
        XCTAssertEqual(p.count, 80)
    }

    func testSingleFrame() {
        var parser = CameraFrameParser()
        let r = parser.append(frame(jpegA))
        XCTAssertEqual(r.frames, [Data(jpegA)])
        XCTAssertFalse(r.malformed)
    }

    func testFrameSplitAcrossReads() {
        var parser = CameraFrameParser()
        let bytes = frame(jpegA)
        var got: [Data] = []
        for b in bytes { got += parser.append(Data([b])).frames }   // one byte at a time
        XCTAssertEqual(got, [Data(jpegA)])
    }

    func testTwoFramesInOneRead() {
        var parser = CameraFrameParser()
        let r = parser.append(frame(jpegA) + frame(jpegB))
        XCTAssertEqual(r.frames, [Data(jpegA), Data(jpegB)])
    }

    func testPartialHeaderWaits() {
        var parser = CameraFrameParser()
        XCTAssertEqual(parser.append(frame(jpegA).prefix(10)).frames, [])
    }

    func testOversizedFrameIsMalformed() {
        var parser = CameraFrameParser()
        let huge = Data([0xFF, 0xFF, 0xFF, 0x7F] + [UInt8](repeating: 0, count: 12))
        XCTAssertTrue(parser.append(huge).malformed)
    }

    func testNonJPEGPayloadIsMalformed() {
        var parser = CameraFrameParser()
        XCTAssertTrue(parser.append(frame([1, 2, 3, 4, 5])).malformed)
    }
}
