// Generates Resources/AppIcon.icns — run: swift make_icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let u = s / 1024
    // Squircle background
    let bg = NSBezierPath(roundedRect: NSRect(x: 100*u, y: 100*u, width: 824*u, height: 824*u), xRadius: 185*u, yRadius: 185*u)
    NSGradient(colors: [NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.24, alpha: 1),
                        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)])!.draw(in: bg, angle: -90)
    func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x*u, y: y*u, width: w*u, height: h*u), xRadius: r*u, yRadius: r*u)
    }
    // Side panel (dark) + warm-grey front, like the P1S
    NSColor(white: 0.07, alpha: 1).setFill(); rr(560, 230, 270, 570, 50).fill()
    NSColor(calibratedRed: 0.36, green: 0.33, blue: 0.30, alpha: 1).setFill(); rr(190, 210, 520, 580, 60).fill()
    // Lit glass door
    let glass = rr(235, 265, 430, 430, 14)
    NSGradient(colors: [NSColor(calibratedRed: 1, green: 0.95, blue: 0.70, alpha: 1),
                        NSColor(calibratedRed: 0.97, green: 0.70, blue: 0.28, alpha: 1)])!.draw(in: glass, angle: -90)
    // Toolhead, bed and part inside the chamber
    NSColor(white: 0.18, alpha: 1).setFill(); rr(430, 560, 90, 70, 12).fill()
    NSColor(white: 0.55, alpha: 1).setFill(); NSRect(x: 235*u, y: 650*u, width: 430*u, height: 14*u).fill()
    NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.15, alpha: 1).setFill(); rr(465, 535, 20, 30, 4).fill()
    NSColor(white: 0.30, alpha: 1).setFill(); rr(265, 330, 370, 36, 8).fill()
    NSColor(calibratedRed: 0.1, green: 0.62, blue: 0.58, alpha: 1).setFill(); rr(400, 366, 110, 90, 10).fill()
    // Handle and display
    NSColor(white: 0.88, alpha: 1).setFill(); rr(590, 470, 90, 30, 15).fill()
    NSColor(white: 0.97, alpha: 1).setFill(); rr(225, 715, 120, 50, 8).fill()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = "Resources/AppIcon.iconset"
try? fm.removeItem(atPath: set)
try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
t.arguments = ["-c", "icns", set, "-o", "Resources/AppIcon.icns"]
try! t.run(); t.waitUntilExit()
try? fm.removeItem(atPath: set)
