import SwiftUI

/// A drawn Bambu Lab P1S (front view): graphite frame, smoked-glass chamber, top lid and a small front display.
/// Temperatures sit on the parts they belong to, and the chamber light lives in the chamber.
struct PrinterFlatView: View {
    @EnvironmentObject var p: Printer

    private var printing: Bool { ["RUNNING", "PREPARE"].contains(p.gcodeState) }
    private let frame = Color(white: 0.11)

    var body: some View {
        VStack(spacing: 0) {
            lid
            chamber
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 9)
            base
        }
        .frame(height: PrinterRig.viewHeight + PrinterRig.captionRowHeight)   // same total height as the 3D view, so the popover does not resize when switching
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.18), frame], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }

    // MARK: Parts

    /// Tinted top lid
    private var lid: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
            .frame(height: 9)
            .padding(.horizontal, 6).padding(.top, 5).padding(.bottom, 4)
    }

    private var chamber: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let on = p.lightOn
            let railY = h * 0.27
            let headX = w * 0.45
            ZStack {
                // Smoked glass, brightened by the chamber light
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        colors: on ? [Color(red: 1, green: 0.99, blue: 0.96), Color(red: 0.92, green: 0.91, blue: 0.88)]
                                   : [Color(white: 0.16), Color(white: 0.06)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: on ? .white.opacity(0.35) : .clear, radius: 12)

                // Z lead screws at the sides
                ForEach([6.0, w - 6.0], id: \.self) { x in
                    Rectangle().fill(Color(white: on ? 0.55 : 0.28)).frame(width: 2.5, height: h - 10).position(x: x, y: h / 2)
                }

                // LED strip under the lid
                Capsule()
                    .fill(on ? Color.white : Color(white: 0.22))
                    .frame(width: w * 0.8, height: 3)
                    .shadow(color: on ? .white : .clear, radius: 5)
                    .position(x: w / 2, y: 7)

                // X-axis carbon rod
                Rectangle().fill(Color(white: on ? 0.40 : 0.30)).frame(width: w - 12, height: 4).position(x: w / 2, y: railY)

                // Toolhead
                toolhead(on: on).position(x: headX, y: railY + 22)

                // Textured build plate on the heated bed
                RoundedRectangle(cornerRadius: 2)
                    .fill(bedColor)
                    .frame(width: w * 0.80, height: 8)
                    .position(x: w / 2, y: h - 18)
                Rectangle().fill(Color(white: on ? 0.35 : 0.22)).frame(width: w * 0.86, height: 5)
                    .position(x: w / 2, y: h - 11)
                if printing {
                    RoundedRectangle(cornerRadius: 3).fill(Color.teal.opacity(0.9))
                        .frame(width: 30, height: 24).position(x: headX, y: h - 34)
                }

                // Glass gloss
                Path { p in
                    p.move(to: CGPoint(x: w * 0.12, y: 0)); p.addLine(to: CGPoint(x: w * 0.42, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.12, y: h)); p.addLine(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h * 0.5)); p.closeSubpath()
                }
                .fill(.white.opacity(on ? 0.12 : 0.06))
                .allowsHitTesting(false)

                // Door frame
                RoundedRectangle(cornerRadius: 4).strokeBorder(Color(white: 0.07), lineWidth: 3)

                // Temperatures
                pill(icon: "flame", name: "Nozzle", value: p.nozzle, target: p.nozzleTarget)
                    .position(x: min(headX + 74, w - 56), y: railY + 22)
                pill(icon: "square.stack.3d.up", name: "Bed", value: p.bed, target: p.bedTarget)
                    .position(x: w - 62, y: h - 40)
                if p.model.hasChamberSensor {
                    pill(icon: "thermometer.medium", name: "Chamber", value: p.chamber, target: nil)
                    .position(x: w - 42, y: 26)
                }

                // Light switch
                Button { p.setLight(!p.lightOn) } label: {
                    Image(systemName: on ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? Color.black.opacity(0.75) : .white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(on ? .white.opacity(0.9) : .white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .disabled(!p.connected)
                .help(on ? "Turn chamber light off" : "Turn chamber light on")
                .accessibilityLabel("Chamber light")
                .accessibilityValue(on ? "On" : "Off")
                .position(x: 28, y: 34)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: p.lightOn)
    }

    /// P1S toolhead: dark carriage with a front fan duct and the hotend underneath
    private func toolhead(on: Bool) -> some View {
        let hot = (p.nozzle ?? 0) > 50
        return VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(white: on ? 0.20 : 0.42))
                Circle().strokeBorder(Color.teal.opacity(0.9), lineWidth: 2).frame(width: 12, height: 12)
            }
            .frame(width: 34, height: 22)
            Rectangle().fill(Color(white: 0.55)).frame(width: 9, height: 5)
            Triangle().fill(hot ? Color.red : Color(white: 0.65)).frame(width: 7, height: 6)
                .shadow(color: hot ? .red : .clear, radius: 5)
        }
    }

    private var bedColor: Color {
        let f = min(max(((p.bed ?? 20) - 25) / 80, 0), 1)
        return Color(red: 0.55 + 0.4 * f, green: 0.50 - 0.2 * f, blue: 0.30 - 0.15 * f)
    }

    private func pill(icon: String, name: String, value: Double?, target: Double?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(value.map { String(format: "%.0f°", $0) } ?? "–").bold()
            if let t = target, t > 0 { Text(String(format: "→%.0f°", t)).opacity(0.7) }
        }
        .font(.system(size: 11, design: .rounded)).monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.72)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenTemp(name, value, target))
    }

    /// Base: model name on the left, the small front display on the right
    private var base: some View {
        HStack(spacing: 8) {
            Text(p.model.name).font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(printing ? Color.green : Color.gray).frame(width: 5, height: 5)
                Text(displayText).lineLimit(1)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(printing ? Color.green : Color(white: 0.7))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 3).fill(.black))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.12)))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var displayText: String {
        let state = p.gcodeState.isEmpty ? "Idle" : p.gcodeState.capitalized
        guard printing else { return state }
        var t = p.progress.map { "\($0)%" } ?? state
        if let r = p.remainingMinutes, r > 0 { t += " · \(r / 60)h\(String(format: "%02d", r % 60))m" }
        return t
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
