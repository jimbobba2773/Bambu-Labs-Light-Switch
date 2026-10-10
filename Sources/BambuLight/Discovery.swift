import Foundation
import Network

struct DiscoveredPrinter: Identifiable, Hashable {
    let id: String      // serial number
    let ip: String
    let name: String
}

/// Finds Bambu printers on the local network via SSDP: listens for their NOTIFY broadcasts and sends an M-SEARCH.
/// Everything received is untrusted network input; it is only used to pre-fill the IP and serial fields.
@MainActor
final class PrinterDiscovery: ObservableObject {
    @Published var found: [DiscoveredPrinter] = []
    @Published var scanning = false

    private nonisolated static let address = "239.255.255.250"
    private nonisolated static let ports: [UInt16] = [1990, 2021]
    private var groups: [NWConnectionGroup] = []
    private let queue = DispatchQueue(label: "ssdp")

    func start() {
        stop()
        scanning = true
        for port in Self.ports {
            guard let p = NWEndpoint.Port(rawValue: port),
                  let mc = try? NWMulticastGroup(for: [.hostPort(host: NWEndpoint.Host(Self.address), port: p)]) else { continue }
            let group = NWConnectionGroup(with: mc, using: .udp)
            group.setReceiveHandler(maximumMessageSize: 4096, rejectOversizedMessages: true) { [weak self] _, content, _ in
                guard let content, let found = Self.parse(content) else { return }
                Task { @MainActor in self?.add(found) }
            }
            group.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                let search = "M-SEARCH * HTTP/1.1\r\nHOST: \(Self.address):\(port)\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: urn:bambulab-com:device:3dprinter:1\r\n\r\n"
                group.send(content: Data(search.utf8)) { _ in }
            }
            group.start(queue: queue)
            groups.append(group)
        }
        // Stop listening after a while; the settings form restarts it when reopened.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            self?.stop()
        }
    }

    func stop() {
        groups.forEach { $0.cancel() }
        groups = []
        scanning = false
    }

    private func add(_ p: DiscoveredPrinter) {
        if let i = found.firstIndex(where: { $0.id == p.id }) { found[i] = p } else { found.append(p) }
    }

    /// Parses an SSDP NOTIFY / search response. Returns nil unless it looks like a Bambu printer with a valid IPv4 and serial.
    nonisolated static func parse(_ data: Data) -> DiscoveredPrinter? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var h: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n").dropFirst() {
            guard let c = line.firstIndex(of: ":") else { continue }
            h[line[..<c].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        guard (h["nt"] ?? h["st"] ?? "").contains("bambulab"),
              let usn = h["usn"], usn.count <= 32, usn.allSatisfy({ $0.isLetter || $0.isNumber }),
              let loc = h["location"], IPv4Address(loc) != nil else { return nil }
        let name = h["devname.bambu.com"].flatMap { $0.isEmpty ? nil : String($0.prefix(40)) } ?? usn
        return DiscoveredPrinter(id: usn, ip: loc, name: name)
    }
}
