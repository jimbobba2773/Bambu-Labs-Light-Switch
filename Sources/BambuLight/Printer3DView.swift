import SwiftUI
import SceneKit

struct SceneContainer: NSViewRepresentable {
    var model: PrinterModel
    var lightOn: Bool
    var nozzleHeat: Double
    var bedHeat: Double
    var printing: Bool

    final class Coordinator {
        let rig: PrinterRig
        init(model: PrinterModel) { rig = PrinterRig(model: model) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> SCNView {
        let rig = context.coordinator.rig
        let v = SCNView(frame: .zero)
        v.scene = rig.scene
        v.pointOfView = rig.camera
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = false
        v.rendersContinuously = false
        v.layer?.isOpaque = false
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        context.coordinator.rig.update(lightOn: lightOn, nozzleHeat: nozzleHeat, bedHeat: bedHeat, printing: printing)
        v.needsDisplay = true
    }
}

/// 3D P1S with labelled callouts: temperatures point at the nozzle, bed and chamber; the light switch points at the LED strip.
struct Printer3DView: View {
    @EnvironmentObject var p: Printer

    private var printing: Bool { ["RUNNING", "PREPARE"].contains(p.gcodeState) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                SceneContainer(model: p.model,
                               lightOn: p.lightOn,
                               nozzleHeat: min(max(((p.nozzle ?? 0) - 40) / 160, 0), 1),
                               bedHeat: min(max(((p.bed ?? 0) - 35) / 70, 0), 1),
                               printing: printing)
                .id(p.model)   // rebuild the scene when the model changes
                GeometryReader { g in callouts(size: g.size) }
            }
            .frame(height: PrinterRig.viewHeight)

            HStack {
                Text(p.gcodeState.isEmpty ? "Idle" : p.gcodeState.capitalized)
                Spacer()
                if printing, let pr = p.progress { Text("\(pr)%") }
                if printing, let r = p.remainingMinutes, r > 0 { Text("· \(r / 60)h \(r % 60)m left") }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    // MARK: Callouts

    private func callouts(size: CGSize) -> some View {
        func pt(_ k: String) -> CGPoint { PrinterRig.project(PrinterRig.anchors[k]!, in: size) }
        let chamber = pt("chamber"), nozzle = pt("nozzle"), bed = pt("bed")
        // Labels are about 66x36pt; keep their centres far enough from the edges that they never clip.
        func inside(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, 40), size.width - 40), y: min(max(p.y, 22), size.height - 22))
        }
        let leftX: CGFloat = 50, rightX = size.width - 50
        let lightPos = inside(CGPoint(x: size.width - 50, y: size.height - 26))
        let chamberPos = inside(CGPoint(x: leftX, y: chamber.y + 26))
        let nozzlePos = inside(CGPoint(x: rightX, y: nozzle.y - 16))
        let bedPos = inside(CGPoint(x: rightX, y: bed.y + 22))
        return ZStack {
            if p.model.hasChamberSensor { leader(from: chamberPos, to: chamber) }
            leader(from: nozzlePos, to: nozzle)
            leader(from: bedPos, to: bed)

            lightButton.position(lightPos)
            if p.model.hasChamberSensor { tempLabel("Chamber", p.chamber, nil).position(chamberPos) }
            tempLabel("Nozzle", p.nozzle, p.nozzleTarget).position(nozzlePos)
            tempLabel("Bed", p.bed, p.bedTarget).position(bedPos)
        }
    }

    private func leader(from: CGPoint, to: CGPoint) -> some View {
        ZStack {
            Path { $0.move(to: from); $0.addLine(to: to) }
                .stroke(.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            Circle().fill(.primary.opacity(0.85)).frame(width: 5, height: 5).position(to)
        }
        .allowsHitTesting(false)
    }

    private func tempLabel(_ name: String, _ value: Double?, _ target: Double?) -> some View {
        VStack(spacing: 1) {
            Text(name.uppercased()).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Text(value.map { String(format: "%.0f°", $0) } ?? "–").font(.system(size: 15, weight: .semibold, design: .rounded))
                if let t = target, t > 0 { Text(String(format: "→%.0f°", t)).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(minWidth: 66)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenTemp(name, value, target))
    }

    private var lightButton: some View {
        let on = p.lightOn
        return Button { p.setLight(!on) } label: {
            VStack(spacing: 1) {
                Text("LIGHT").font(.system(size: 8, weight: .semibold)).foregroundStyle(on ? Color.black.opacity(0.6) : .secondary)
                HStack(spacing: 4) {
                    Image(systemName: on ? "lightbulb.fill" : "lightbulb").font(.system(size: 13))
                    Text(on ? "On" : "Off").font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(on ? Color.black : .primary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(minWidth: 66)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.regularMaterial)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!p.connected)
        .help(on ? "Turn chamber light off" : "Turn chamber light on")
        .accessibilityLabel("Light")
        .accessibilityValue(on ? "On" : "Off")
    }
}
