import SwiftUI
import ServiceManagement
import os

enum Log {
    static let app = Logger(subsystem: "local.bambulight", category: "app")
}

@main
struct BambuLightApp: App {
    @StateObject private var printer = Printer()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(printer)
        } label: {
            Image(systemName: !printer.connected ? "lightbulb.slash" : printer.lightOn ? "lightbulb.fill" : "lightbulb")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var p: Printer
    @AppStorage("flatView") private var flatView = false
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusChip()
                Spacer()
                if showSettings && p.isConfigured {
                    Button("Done") { showSettings = false }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.borderedProminent).controlSize(.small)
                } else if !showSettings {
                    Button { showSettings = true } label: { Image(systemName: "gearshape").imageScale(.large) }
                        .buttonStyle(.plain)
                        .help("Settings")
                        .accessibilityLabel("Settings")
                }
            }

            if showSettings || !p.isConfigured {
                ScrollView {
                    SettingsForm(done: { showSettings = false })
                        .padding(.trailing, 6)
                }
                // Same total height as the printer view (scene + caption row), so switching never resizes the popover.
                .frame(height: PrinterRig.viewHeight + PrinterRig.captionRowHeight)
            } else {
                if flatView { PrinterFlatView() } else { Printer3DView() }
            }

            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 360)
    }
}

/// Prominent connection state: colour + icon + plain-language text, so "offline" and "error" are easy to tell apart.
struct StatusChip: View {
    @EnvironmentObject var p: Printer

    private var look: (icon: String, color: Color, text: String) {
        switch p.health {
        case .ok: ("checkmark.circle.fill", .green, "Connected")
        case .busy: ("arrow.triangle.2.circlepath", .orange, p.status)
        case .offline: ("wifi.slash", .orange, p.status.hasPrefix("Reconnecting") ? "Printer offline · \(p.status.lowercased())" : "Printer offline")
        case .error: ("exclamationmark.triangle.fill", .red, p.status)
        case .idle: ("gearshape", .secondary, "Not configured")
        }
    }

    var body: some View {
        let l = look
        HStack(spacing: 5) {
            Image(systemName: l.icon)
            Text(l.text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(l.color)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(l.color.opacity(0.14)))
        .help(p.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection status")
        .accessibilityValue(l.text)
    }
}

struct SettingsForm: View {
    @EnvironmentObject var p: Printer
    @State private var password = ""
    @State private var code = ""
    @StateObject private var discovery = PrinterDiscovery()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @AppStorage("flatView") private var flatView = false
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: p.$mode) {
                Text("Local (LAN)").tag("lan")
                Text("Bambu Cloud").tag("cloud")
            }
            .pickerStyle(.segmented).labelsHidden()

            if p.mode == "cloud" { cloudForm } else { lanForm }

            Picker("Model", selection: p.$modelChoice) {
                Text("Auto (\(PrinterModel.detect(serial: p.serial)?.name ?? "P1S"))").tag("auto")
                ForEach(PrinterModel.allCases) { Text($0.name).tag($0.rawValue) }
            }
            Divider()
            Toggle("Simple flat view (instead of 3D)", isOn: $flatView)
            Toggle("Notify when a print finishes or fails", isOn: p.$notifyPrints)
            Toggle("Shortcut ⌃⌥L toggles the light", isOn: p.$lightHotkey)
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    launchError = nil
                } catch {
                    Log.app.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
                    launchError = "Couldn't change launch at login: \(error.localizedDescription)"
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }))
            if let launchError { Text(launchError).font(.caption).foregroundStyle(.red) }
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: p.mode) { _ in p.modeChanged() }
        .onChange(of: p.notifyPrints) { _ in p.applyPreferences() }
        .onChange(of: p.lightHotkey) { _ in p.applyPreferences() }
        .task { if p.mode == "cloud", !p.cloudToken.isEmpty, p.devices.isEmpty { p.refreshDevices() } }
    }

    private var lanForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            discoveryMenu
            TextField("IP address", text: p.$host)
            TextField("Serial number", text: p.$serial)
            SecureField("Access code", text: $p.accessCode)
            Text("Find all three on the printer: Settings → WLAN / LAN. Enable LAN Mode.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Save & Connect") { p.saveAndConnect(); done() }
                    .disabled(p.host.isEmpty || p.serial.isEmpty || p.accessCode.isEmpty)
                Button("Forget certificate") { p.forgetCertificate() }
                    .disabled(p.serial.isEmpty)
                    .help("Use if the printer was replaced or reset and shows “Certificate changed”")
            }
        }
    }

    private var discoveryMenu: some View {
        HStack {
            Menu(discovery.found.isEmpty ? "Find printers" : "Printers found (\(discovery.found.count))") {
                ForEach(discovery.found) { d in
                    Button("\(d.name) · \(d.ip)") { p.host = d.ip; p.serial = d.id }
                }
            }
            .disabled(discovery.found.isEmpty)
            if discovery.scanning { ProgressView().controlSize(.small) }
            else { Button("Rescan") { discovery.start() }.buttonStyle(.link) }
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    @ViewBuilder private var cloudForm: some View {
        if p.cloudToken.isEmpty {
            switch p.cloudStep {
            case .credentials:
                Picker("Region", selection: p.$cloudRegion) {
                    ForEach(CloudRegion.allCases) { Text($0.label).tag($0.rawValue) }
                }
                TextField("Bambu account email", text: p.$cloudEmail)
                SecureField("Password", text: $password)
                Button("Sign in") { p.signIn(password: password); password = "" }
                    .disabled(p.cloudEmail.isEmpty || password.isEmpty || p.cloudBusy)
            case .needsCode, .needsTFA:
                Text(isTFA ? "Enter your two-factor code." : "We emailed you a verification code.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Code", text: $code)
                HStack {
                    Button("Verify") { p.submitCode(code); code = "" }
                        .disabled(code.isEmpty || p.cloudBusy)
                    Button("Back") { p.cloudStep = .credentials }
                }
            }
        } else {
            if p.devices.isEmpty {
                Text(p.cloudBusy ? "Loading printers…" : "No printers found on this account.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Printer", selection: p.$serial) {
                    ForEach(p.devices) { Text($0.name).tag($0.id) }
                }
            }
            HStack {
                Button("Save & Connect") { p.connect(); done() }.disabled(p.serial.isEmpty)
                Button("Sign out") { p.signOut() }
            }
        }
        if p.cloudBusy { ProgressView().controlSize(.small) }
        if let e = p.cloudError { Text(e).font(.caption).foregroundStyle(.red) }
    }

    private var isTFA: Bool { if case .needsTFA = p.cloudStep { return true }; return false }
}
