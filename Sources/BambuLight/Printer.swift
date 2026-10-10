import Foundation
import SwiftUI
import Security

@MainActor
final class Printer: ObservableObject {
    @Published var status = "Not configured"
    @Published var connected = false
    @Published var nozzle: Double?
    @Published var nozzleTarget: Double?
    @Published var bed: Double?
    @Published var bedTarget: Double?
    @Published var chamber: Double?
    @Published var lightOn = false
    @Published var gcodeState = ""
    @Published var progress: Int?
    @Published var remainingMinutes: Int?

    enum CloudStep { case credentials, needsCode, needsTFA(String) }

    @AppStorage("mode") var mode = "lan"          // "lan" or "cloud"
    @AppStorage("host") var host = ""
    @AppStorage("serial") var serial = ""
    @AppStorage("cloudUid") var cloudUid = ""
    @AppStorage("cloudEmail") var cloudEmail = ""
    @AppStorage("cloudRegion") var cloudRegion = CloudRegion.global.rawValue
    @AppStorage("notifyPrints") var notifyPrints = true
    @AppStorage("lightHotkey") var lightHotkey = true
    @AppStorage("modelChoice") var modelChoice = "auto"   // "auto" = detect from the serial number
    @Published var accessCode: String = Keychain.read("accessCode") ?? ""
    @Published var cloudToken: String = Keychain.read("cloudToken") ?? ""
    @Published var cloudStep: CloudStep = .credentials
    @Published var cloudBusy = false
    @Published var cloudError: String?
    @Published var devices: [CloudDevice] = []

    private let mqtt = MQTTClient()
    private var pendingLight: (state: Bool, until: Date)?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let hotKey = HotKey()

    init() {
        mqtt.onState = { [weak self] s in
            Task { @MainActor in self?.handleState(s) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isConfigured else { return }
                self.reconnectAttempt = 0
                self.connect()
            }
        }
        mqtt.onMessage = { [weak self] _, data in
            Task { @MainActor in self?.handle(data) }
        }
        hotKey.onPress = { [weak self] in Task { @MainActor in self?.toggleFromHotKey() } }
        applyPreferences()
        if isConfigured { connect() }
    }

    var model: PrinterModel { PrinterModel(rawValue: modelChoice) ?? PrinterModel.detect(serial: serial) ?? .p1s }

    private var api: CloudAPI { CloudAPI(region: CloudRegion(rawValue: cloudRegion) ?? .global) }

    enum Health { case ok, busy, offline, error, idle }

    /// Coarse connection state for the UI, derived from the status text.
    var health: Health {
        if connected { return .ok }
        if status == "Not configured" { return .idle }
        if status.hasPrefix("Connecting") || status.hasPrefix("Waiting") { return status.hasPrefix("Waiting") ? .offline : .busy }
        if status == "Disconnected" || status.hasPrefix("Reconnecting") || status.hasPrefix("Connection failed") { return .offline }
        return .error
    }

    var isConfigured: Bool {
        mode == "cloud" ? (!cloudToken.isEmpty && !cloudUid.isEmpty && !serial.isEmpty)
                        : (!host.isEmpty && !serial.isEmpty && !accessCode.isEmpty)
    }

    func saveAndConnect() {
        let saved = Keychain.write("accessCode", accessCode)
        connect()
        if !saved { status = "Connecting, but the Keychain write failed" }
    }

    /// Forget the pinned printer certificate (e.g. after a firmware update or printer replacement) and reconnect.
    func forgetCertificate() {
        CertPins.forget(serial)
        connect()
    }

    /// Registers or removes the global shortcut and asks for notification permission, per the current settings.
    func applyPreferences() {
        if lightHotkey { hotKey.register() } else { hotKey.unregister() }
        if notifyPrints { Notifier.requestPermission() }
    }

    private func toggleFromHotKey() {
        if connected { setLight(!lightOn) }
    }

    private func handleState(_ s: String) {
        status = s
        connected = (s == "Connected")
        if s == "Connected" {
            reconnectAttempt = 0
            requestFullStatus()
        } else if s == "Disconnected" || s.hasPrefix("Connection failed") {
            scheduleReconnect()
        } else if s == "Rejected — check credentials" {
            reconnectTask?.cancel()
            if mode == "cloud" {
                // Cloud tokens expire; force a fresh sign-in.
                signOut()
                cloudError = "Your Bambu Cloud session expired. Please sign in again."
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        guard isConfigured else { return }
        let delay = min(60.0, 2.0 * pow(2.0, Double(reconnectAttempt)))
        reconnectAttempt += 1
        status = "Reconnecting in \(Int(delay))s…"
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.connect()
        }
    }

    /// Called when the LAN/Cloud picker changes: drop the old session and join the new one if it's ready.
    func modeChanged() {
        reconnectTask?.cancel()
        reconnectAttempt = 0
        mqtt.disconnect()
        connected = false
        if isConfigured { connect() } else { status = "Not configured" }
    }

    func connect() {
        reconnectTask?.cancel()
        guard isConfigured else { status = "Not configured"; return }
        let topics = ["device/\(serial)/report"]
        if mode == "cloud" {
            mqtt.connect(host: api.mqttHost, verifyCert: true, username: "u_\(cloudUid)",
                         password: cloudToken, subscribe: topics)
        } else {
            let key = serial
            mqtt.connect(host: host.trimmingCharacters(in: .whitespaces), pin: { CertPins.check(key, $0) }, username: "bblp",
                         password: accessCode, subscribe: topics)
        }
    }

    // MARK: Cloud sign-in

    private func cloud(_ work: @escaping () async throws -> Void) {
        cloudBusy = true; cloudError = nil
        Task {
            do { try await work() } catch { cloudError = error.localizedDescription }
            cloudBusy = false
        }
    }

    private func finishSignIn(token: String) async throws {
        let uid = try await api.userId(token: token)
        guard Keychain.write("cloudToken", token) else {
            throw CloudError.message("Couldn't save your sign-in to the Keychain. Check that BambuLight is allowed to use it.")
        }
        cloudToken = token; cloudUid = uid; cloudStep = .credentials
        try await loadDevices()
    }

    func signIn(password: String) {
        let email = cloudEmail.trimmingCharacters(in: .whitespaces)
        cloud {
            switch try await self.api.login(email: email, password: password) {
            case .token(let t): try await self.finishSignIn(token: t)
            case .needsCode:
                try await self.api.sendCode(email: email)
                self.cloudStep = .needsCode
            case .needsTFA(let key): self.cloudStep = .needsTFA(key)
            }
        }
    }

    func submitCode(_ code: String) {
        let email = cloudEmail.trimmingCharacters(in: .whitespaces)
        let step = cloudStep
        cloud {
            switch step {
            case .needsTFA(let key): try await self.finishSignIn(token: self.api.tfa(key: key, code: code))
            default: try await self.finishSignIn(token: self.api.login(email: email, code: code))
            }
        }
    }

    func refreshDevices() { cloud { try await self.loadDevices() } }

    private func loadDevices() async throws {
        devices = try await api.devices(token: cloudToken)
        if serial.isEmpty || !devices.contains(where: { $0.id == serial }) { serial = devices.first?.id ?? "" }
    }

    func signOut() {
        reconnectTask?.cancel()
        mqtt.disconnect()
        Keychain.write("cloudToken", "")
        cloudToken = ""; cloudUid = ""; devices = []; cloudStep = .credentials
        connected = false; status = "Not configured"
    }

    func requestFullStatus() {
        send(["pushing": ["sequence_id": "1", "command": "pushall"]])
    }

    func setLight(_ on: Bool) {
        lightOn = on
        pendingLight = (on, Date().addingTimeInterval(3)) // ignore stale reports briefly
        // If the printer never confirms, resync (or roll back when offline) instead of showing a wrong state.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, let pend = self.pendingLight, pend.state == on else { return }
            self.pendingLight = nil
            if self.connected { self.requestFullStatus() } else { self.lightOn = !on }
        }
        send(["system": ["sequence_id": "0", "command": "ledctrl", "led_node": model.lightNode,
                         "led_mode": on ? "on" : "off", "led_on_time": 500, "led_off_time": 500,
                         "loop_times": 0, "interval_time": 0]])
    }

    private func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        mqtt.publish(topic: "device/\(serial)/request", payload: data)
    }

    private func notifyIfPrintEnded(from old: String, to new: String) {
        guard notifyPrints, ["RUNNING", "PREPARE", "PAUSE"].contains(old), old != new else { return }
        switch new {
        case "FINISH": Notifier.post(title: "Print finished", body: "\(model.name) has finished printing.")
        case "FAILED": Notifier.post(title: "Print failed", body: "\(model.name) stopped with an error.")
        default: break
        }
    }

    private func handle(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = root["print"] as? [String: Any] else { return }
        func num(_ k: String) -> Double? { (p[k] as? NSNumber)?.doubleValue }
        if let v = num("nozzle_temper") { nozzle = v }
        if let v = num("nozzle_target_temper") { nozzleTarget = v }
        if let v = num("bed_temper") { bed = v }
        if let v = num("bed_target_temper") { bedTarget = v }
        if let v = num("chamber_temper") { chamber = v }
        if let v = p["gcode_state"] as? String {
            notifyIfPrintEnded(from: gcodeState, to: v)
            gcodeState = v
        }
        if let v = num("mc_percent") { progress = Int(v) }
        if let v = num("mc_remaining_time") { remainingMinutes = Int(v) }
        if let lights = p["lights_report"] as? [[String: Any]],
           let l = lights.first(where: { $0["node"] as? String == model.lightNode }),
           let mode = l["mode"] as? String {
            let reported = (mode == "on")
            if let pend = pendingLight {
                if reported == pend.state { pendingLight = nil }   // confirmed
                else if pend.until > Date() { return }
                else { pendingLight = nil }
            }
            lightOn = reported
        }
    }
}

enum Keychain {
    static func read(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "BambuLight", kSecAttrAccount as String: key,
                                kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    @discardableResult
    static func write(_ key: String, _ value: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "BambuLight", kSecAttrAccount as String: key]
        let deleted = SecItemDelete(base as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { return false }
        if value.isEmpty { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// Trust-on-first-use pinning of the printer's self-signed certificate (SHA-256 of the leaf), keyed by serial.
enum CertPins {
    private static func key(_ serial: String) -> String { "certPin.\(serial)" }
    /// Called from the network queue. First sight of a printer pins it; later connections must match.
    static func check(_ serial: String, _ fingerprint: String) -> Bool {
        if let pinned = UserDefaults.standard.string(forKey: key(serial)) { return pinned == fingerprint }
        UserDefaults.standard.set(fingerprint, forKey: key(serial))
        return true
    }
    static func forget(_ serial: String) { UserDefaults.standard.removeObject(forKey: key(serial)) }
}
