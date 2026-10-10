import XCTest
@testable import BambuLight

final class DiscoveryParseTests: XCTestCase {
    private func notify(_ extra: String = "", usn: String = "01P00A123456789", location: String = "192.168.1.50",
                        nt: String = "urn:bambulab-com:device:3dprinter:1") -> Data {
        Data("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1990\r\nNT: \(nt)\r\nUSN: \(usn)\r\nLocation: \(location)\r\n\(extra)\r\n".utf8)
    }

    func testParsesPrinter() {
        let p = PrinterDiscovery.parse(notify("DevName.bambu.com: Workshop\r\n"))
        XCTAssertEqual(p, DiscoveredPrinter(id: "01P00A123456789", ip: "192.168.1.50", name: "Workshop"))
    }

    func testHeaderNamesAreCaseInsensitiveAndNameFallsBackToSerial() {
        let data = Data("NOTIFY * HTTP/1.1\r\nnt: urn:bambulab-com:device:3dprinter:1\r\nusn: ABC123\r\nLOCATION: 10.0.0.2\r\n\r\n".utf8)
        XCTAssertEqual(PrinterDiscovery.parse(data)?.name, "ABC123")
    }

    func testRejectsOtherDevices() { XCTAssertNil(PrinterDiscovery.parse(notify(nt: "upnp:rootdevice"))) }
    func testRejectsBadIP() {
        XCTAssertNil(PrinterDiscovery.parse(notify(location: "evil.example.com")))
        XCTAssertNil(PrinterDiscovery.parse(notify(location: "999.1.1.1")))
    }
    func testRejectsBadSerial() {
        XCTAssertNil(PrinterDiscovery.parse(notify(usn: "../../etc")))
        XCTAssertNil(PrinterDiscovery.parse(notify(usn: String(repeating: "A", count: 64))))
    }
    func testRejectsNonUTF8() { XCTAssertNil(PrinterDiscovery.parse(Data([0xFF, 0xFE, 0x00]))) }
    func testNameIsTruncated() {
        let p = PrinterDiscovery.parse(notify("DevName.bambu.com: \(String(repeating: "x", count: 200))\r\n"))
        XCTAssertEqual(p?.name.count, 40)
    }
}

final class PrinterModelTests: XCTestCase {
    func testDetectFromSerialPrefix() {
        XCTAssertEqual(PrinterModel.detect(serial: "01P00A000000001"), .p1s)
        XCTAssertEqual(PrinterModel.detect(serial: "01s00abc"), .p1p)
        XCTAssertEqual(PrinterModel.detect(serial: "00M00A1"), .x1c)
        XCTAssertEqual(PrinterModel.detect(serial: "030ABC"), .a1mini)
        XCTAssertEqual(PrinterModel.detect(serial: "039ABC"), .a1)
        XCTAssertNil(PrinterModel.detect(serial: "ZZZ"))
        XCTAssertNil(PrinterModel.detect(serial: ""))
    }

    func testLightNodeAndChamberSensor() {
        XCTAssertEqual(PrinterModel.p1s.lightNode, "chamber_light")
        XCTAssertEqual(PrinterModel.a1.lightNode, "work_light")
        XCTAssertEqual(PrinterModel.a1mini.lightNode, "work_light")
        XCTAssertTrue(PrinterModel.p1s.hasChamberSensor)
        XCTAssertFalse(PrinterModel.p1p.hasChamberSensor)
        XCTAssertFalse(PrinterModel.a1.hasChamberSensor)
    }

    func testSpokenTemp() {
        XCTAssertEqual(spokenTemp("Nozzle", 215.4, 220), "Nozzle 215 degrees, target 220")
        XCTAssertEqual(spokenTemp("Bed", 60, 0), "Bed 60 degrees")
        XCTAssertEqual(spokenTemp("Chamber", nil, nil), "Chamber temperature unavailable")
    }
}

final class CertPinTests: XCTestCase {
    private let serial = "TEST-\(UUID().uuidString)"
    override func tearDown() { CertPins.forget(serial) }

    func testTrustOnFirstUseThenMustMatch() {
        XCTAssertTrue(CertPins.check(serial, "aaaa"))    // first sight pins
        XCTAssertTrue(CertPins.check(serial, "aaaa"))
        XCTAssertFalse(CertPins.check(serial, "bbbb"))   // changed certificate is refused
    }

    func testForgetAllowsRepinning() {
        _ = CertPins.check(serial, "aaaa")
        CertPins.forget(serial)
        XCTAssertTrue(CertPins.check(serial, "bbbb"))
    }

    func testPinsAreIndependentPerPrinter() {
        let other = serial + "-2"
        defer { CertPins.forget(other) }
        _ = CertPins.check(serial, "aaaa")
        XCTAssertTrue(CertPins.check(other, "bbbb"))
    }
}

final class LightScheduleTests: XCTestCase {
    func testDaytimeWindow() {
        XCTAssertEqual(LightSchedule.shouldBeOn(minute: 8 * 60, on: 8 * 60, off: 18 * 60), true)
        XCTAssertEqual(LightSchedule.shouldBeOn(minute: 12 * 60, on: 8 * 60, off: 18 * 60), true)
        XCTAssertEqual(LightSchedule.shouldBeOn(minute: 18 * 60, on: 8 * 60, off: 18 * 60), false)
        XCTAssertEqual(LightSchedule.shouldBeOn(minute: 7 * 60 + 59, on: 8 * 60, off: 18 * 60), false)
    }

    func testWindowCrossingMidnight() {
        XCTAssertEqual(LightSchedule.shouldBeOn(minute: 23 * 60, on: 20 * 60, off: 6 * 60), true)
        XCTAssertEqual(LightSchedule.shouldBeOn(minute: 2 * 60, on: 20 * 60, off: 6 * 60), true)
        XCTAssertEqual(LightSchedule.shouldBeOn(minute: 6 * 60, on: 20 * 60, off: 6 * 60), false)
        XCTAssertEqual(LightSchedule.shouldBeOn(minute: 12 * 60, on: 20 * 60, off: 6 * 60), false)
    }

    func testEqualTimesMeanNoSchedule() { XCTAssertNil(LightSchedule.shouldBeOn(minute: 100, on: 500, off: 500)) }

    func testMinuteConversionRoundTrip() {
        for m in [0, 59, 60, 725, 1439] { XCTAssertEqual(LightSchedule.minuteOfDay(LightSchedule.date(forMinute: m)), m) }
    }
}

final class LightNodeTests: XCTestCase {
    func testPrefersModelNodeWhenReported() {
        XCTAssertEqual(PrinterModel.chooseLightNode(model: .p1s, reported: ["chamber_light"]), "chamber_light")
        XCTAssertEqual(PrinterModel.chooseLightNode(model: .a1, reported: ["work_light", "chamber_light"]), "work_light")
    }
    func testFallsBackToWhatThePrinterReports() {
        XCTAssertEqual(PrinterModel.chooseLightNode(model: .a1, reported: ["chamber_light"]), "chamber_light")
        XCTAssertEqual(PrinterModel.chooseLightNode(model: .p1s, reported: ["work_light"]), "work_light")
        XCTAssertEqual(PrinterModel.chooseLightNode(model: .p1s, reported: ["strange_light"]), "strange_light")
    }
    func testUsesModelDefaultBeforeAnyReport() {
        XCTAssertEqual(PrinterModel.chooseLightNode(model: .a1mini, reported: []), "work_light")
        XCTAssertEqual(PrinterModel.chooseLightNode(model: .p1s, reported: []), "chamber_light")
    }
    func testOpenFrameModels() {
        XCTAssertTrue(PrinterModel.a1.isOpenFrame); XCTAssertTrue(PrinterModel.a1mini.isOpenFrame)
        XCTAssertFalse(PrinterModel.p1s.isOpenFrame); XCTAssertFalse(PrinterModel.p1p.isOpenFrame)
    }
}
