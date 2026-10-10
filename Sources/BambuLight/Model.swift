import Foundation

/// Printer models differ in which node controls the light and whether there is a chamber sensor.
enum PrinterModel: String, CaseIterable, Identifiable {
    case p1s, p1p, x1c, x1, x1e, a1, a1mini, h2d

    var id: String { rawValue }

    var name: String {
        switch self {
        case .p1s: "P1S"
        case .p1p: "P1P"
        case .x1c: "X1 Carbon"
        case .x1: "X1"
        case .x1e: "X1E"
        case .a1: "A1"
        case .a1mini: "A1 mini"
        case .h2d: "H2D"
        }
    }

    /// The A1 series has an open frame with a work light only; the others have a chamber light.
    var lightNode: String {
        switch self {
        case .a1, .a1mini: "work_light"
        default: "chamber_light"
        }
    }

    var hasChamberSensor: Bool {
        switch self {
        case .p1p, .a1, .a1mini: false
        default: true
        }
    }

    /// Bambu serial numbers start with a model code. Unrecognised prefixes return nil.
    static func detect(serial: String) -> PrinterModel? {
        let prefixes: [(String, PrinterModel)] = [
            ("01P", .p1s), ("01S", .p1p), ("00M", .x1c), ("00W", .x1), ("03W", .x1e),
            ("039", .a1), ("030", .a1mini), ("094", .h2d),
        ]
        let s = serial.uppercased()
        return prefixes.first { s.hasPrefix($0.0) }?.1
    }
}

/// Spoken form of a temperature readout for VoiceOver.
func spokenTemp(_ name: String, _ value: Double?, _ target: Double?) -> String {
    guard let value else { return "\(name) temperature unavailable" }
    var s = "\(name) \(Int(value.rounded())) degrees"
    if let t = target, t > 0 { s += ", target \(Int(t.rounded()))" }
    return s
}
