import SceneKit
import AppKit

/// Procedural 3D model of a Bambu Lab P1S (units ≈ decimetres): graphite frame, smoked-glass door and left panel,
/// opaque right/back panels, and a visible interior — Z screws, X rods, toolhead, heated bed.
/// A real omni light inside the chamber is driven by the light switch.
final class PrinterRig {
    let scene = SCNScene()
    let camera = SCNNode()

    /// Points on the model that the UI points its labels at.
    static let anchors: [String: SCNVector3] = [
        "nozzle": SCNVector3(0.1, 2.28, 0.0),
        "bed": SCNVector3(1.25, 1.18, 1.25),
        "chamber": SCNVector3(-1.0, 2.45, 0.9),
        "light": SCNVector3(-0.8, 3.80, 1.72),
    ]

    static let cameraPosition = SCNVector3(6.8, 5.95, 10.2)
    static let cameraTarget = SCNVector3(0, 1.55, 0)
    static let fieldOfView: CGFloat = 26   // vertical

    /// Height of the 3D scene in the popover; the flat view derives its height from this so switching does not resize the popover.
    static let viewHeight: CGFloat = 330
    /// Height of the status row under the 3D scene (caption text + spacing).
    static let captionRowHeight: CGFloat = 22

    /// Pinhole projection of a model point to view coordinates (origin top-left) — matches the camera above.
    static func project(_ p: SCNVector3, in size: CGSize) -> CGPoint {
        func sub(_ a: SCNVector3, _ b: SCNVector3) -> (CGFloat, CGFloat, CGFloat) { (a.x - b.x, a.y - b.y, a.z - b.z) }
        func norm(_ v: (CGFloat, CGFloat, CGFloat)) -> (CGFloat, CGFloat, CGFloat) {
            let l = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot(); return (v.0 / l, v.1 / l, v.2 / l)
        }
        func cross(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> (CGFloat, CGFloat, CGFloat) {
            (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
        }
        func dot(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> CGFloat { a.0 * b.0 + a.1 * b.1 + a.2 * b.2 }
        let f = norm(sub(cameraTarget, cameraPosition))
        let r = norm(cross(f, (0, 1, 0)))
        let u = cross(r, f)
        let d = sub(p, cameraPosition)
        let t = tan(fieldOfView * .pi / 360)
        let zc = dot(d, f)
        let nx = dot(d, r) / zc / (t * size.width / size.height)
        let ny = dot(d, u) / zc / t
        return CGPoint(x: (nx + 1) / 2 * size.width, y: (1 - ny) / 2 * size.height)
    }

    private let omni = SCNNode()
    private let glassMat = SCNMaterial()
    private let ledMat = SCNMaterial()
    private let nozzleMat = SCNMaterial()
    private let bedMat = SCNMaterial()
    private let part = SCNNode()

    init() {
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Self.studioImage()
        scene.lightingEnvironment.intensity = 0.9

        buildMaterials()
        buildBody()
        buildInterior()
        buildLights()
        buildGround()

        let cam = SCNCamera()
        cam.fieldOfView = Self.fieldOfView
        cam.zNear = 1; cam.zFar = 60
        camera.camera = cam
        camera.position = Self.cameraPosition
        let target = SCNNode(); target.position = Self.cameraTarget
        scene.rootNode.addChildNode(target)
        let look = SCNLookAtConstraint(target: target); look.isGimbalLockEnabled = true
        camera.constraints = [look]
        scene.rootNode.addChildNode(camera)

        update(lightOn: false, nozzleHeat: 0, bedHeat: 0, printing: false, animated: false)
    }

    // MARK: State

    func update(lightOn: Bool, nozzleHeat: Double, bedHeat: Double, printing: Bool, animated: Bool = true) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.35 : 0
        omni.light?.intensity = lightOn ? 850 : 0
        ledMat.emission.contents = lightOn ? NSColor.white : NSColor(white: 0.04, alpha: 1)
        glassMat.emission.contents = lightOn ? NSColor(red: 1, green: 0.96, blue: 0.88, alpha: 1) : NSColor.black
        glassMat.emission.intensity = lightOn ? 0.32 : 0
        glassMat.transparency = lightOn ? 0.62 : 0.34
        nozzleMat.emission.contents = NSColor(red: 1, green: 0.15, blue: 0.05, alpha: 1)
        nozzleMat.emission.intensity = CGFloat(nozzleHeat) * 1.6
        bedMat.emission.contents = NSColor(red: 1, green: 0.40, blue: 0.08, alpha: 1)
        bedMat.emission.intensity = CGFloat(bedHeat) * 1.1
        SCNTransaction.commit()
        part.isHidden = !printing
    }

    // MARK: Build

    private func mat(_ color: NSColor, metal: CGFloat = 0.2, rough: CGFloat = 0.5) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        return m
    }

    private func buildMaterials() {
        glassMat.lightingModel = .blinn
        glassMat.diffuse.contents = NSColor(white: 0.03, alpha: 1)
        glassMat.specular.contents = NSColor(white: 1, alpha: 1)
        glassMat.shininess = 0.9
        glassMat.reflective.contents = Self.studioImage()
        glassMat.reflective.intensity = 0.25
        glassMat.isDoubleSided = true
        glassMat.writesToDepthBuffer = false
        glassMat.transparencyMode = .singleLayer

        ledMat.lightingModel = .constant
        ledMat.diffuse.contents = NSColor(white: 0.1, alpha: 1)

        nozzleMat.lightingModel = .physicallyBased
        nozzleMat.diffuse.contents = NSColor(white: 0.7, alpha: 1)
        nozzleMat.metalness.contents = 0.9; nozzleMat.roughness.contents = 0.3

        bedMat.lightingModel = .physicallyBased
        bedMat.diffuse.contents = NSColor(white: 0.15, alpha: 1)
        bedMat.metalness.contents = 0.5; bedMat.roughness.contents = 0.85
    }

    @discardableResult
    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, at p: SCNVector3, chamfer: CGFloat = 0.03,
                     _ m: SCNMaterial, in parent: SCNNode? = nil) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        g.materials = [m]
        let n = SCNNode(geometry: g); n.position = p
        (parent ?? scene.rootNode).addChildNode(n)
        return n
    }

    @discardableResult
    private func rod(_ r: CGFloat, _ len: CGFloat, at p: SCNVector3, axis: Character, _ m: SCNMaterial) -> SCNNode {
        let g = SCNCylinder(radius: r, height: len); g.materials = [m]
        let n = SCNNode(geometry: g); n.position = p
        if axis == "x" { n.eulerAngles.z = .pi / 2 } else if axis == "z" { n.eulerAngles.x = .pi / 2 }
        scene.rootNode.addChildNode(n)
        return n
    }

    private func buildBody() {
        let W: CGFloat = 3.9, D: CGFloat = 3.9
        let frame = mat(NSColor(white: 0.13, alpha: 1), metal: 0.35, rough: 0.42)
        let base = mat(NSColor(red: 0.20, green: 0.19, blue: 0.18, alpha: 1), metal: 0.3, rough: 0.5)
        let panel = mat(NSColor(white: 0.07, alpha: 1), metal: 0.3, rough: 0.55)

        // Base, lid, pillars
        box(W, 0.5, D, at: SCNVector3(0, 0.25, 0), chamfer: 0.07, base)
        box(W, 0.16, D, at: SCNVector3(0, 3.92, 0), chamfer: 0.06, frame)
        let pil: CGFloat = 0.17
        for sx: CGFloat in [-1, 1] { for sz: CGFloat in [-1, 1] {
            box(pil, 3.45, pil, at: SCNVector3(sx * (W / 2 - pil / 2), 2.22, sz * (D / 2 - pil / 2)), chamfer: 0.02, frame)
        } }
        // Opaque right and back panels
        box(0.06, 3.4, D - 0.3, at: SCNVector3(W / 2 - 0.04, 2.22, 0), chamfer: 0.01, panel)
        box(W - 0.3, 3.4, 0.06, at: SCNVector3(0, 2.22, -D / 2 + 0.04), chamfer: 0.01, panel)

        // Smoked glass: front door and left panel
        let front = SCNPlane(width: W - 0.3, height: 3.4); front.materials = [glassMat]
        let fn = SCNNode(geometry: front); fn.position = SCNVector3(0, 2.22, D / 2 - 0.03); fn.renderingOrder = 10
        scene.rootNode.addChildNode(fn)
        let left = SCNPlane(width: D - 0.3, height: 3.4); left.materials = [glassMat]
        let ln = SCNNode(geometry: left); ln.position = SCNVector3(-W / 2 + 0.03, 2.22, 0)
        ln.eulerAngles.y = -.pi / 2; ln.renderingOrder = 10
        scene.rootNode.addChildNode(ln)

        // Door handle
        let hm = mat(NSColor(white: 0.85, alpha: 1), metal: 0.1, rough: 0.35)
        let hg = SCNCapsule(capRadius: 0.06, height: 0.55); hg.materials = [hm]
        let hn = SCNNode(geometry: hg); hn.position = SCNVector3(1.55, 2.1, D / 2 + 0.02)
        scene.rootNode.addChildNode(hn)

        // Front display on the lid
        let screen = mat(NSColor(white: 0.93, alpha: 1), metal: 0, rough: 0.3)
        screen.emission.contents = NSColor(white: 0.55, alpha: 1)
        box(0.5, 0.11, 0.03, at: SCNVector3(-1.4, 3.92, D / 2 + 0.005), chamfer: 0.01, screen)

        // LED strips under the lid, front and back
        box(3.2, 0.03, 0.05, at: SCNVector3(0, 3.82, 1.75), chamfer: 0.005, ledMat)
        box(3.2, 0.03, 0.05, at: SCNVector3(0, 3.82, -1.75), chamfer: 0.005, ledMat)
    }

    private func buildInterior() {
        let metal = mat(NSColor(white: 0.62, alpha: 1), metal: 0.95, rough: 0.28)
        let dark = mat(NSColor(white: 0.10, alpha: 1), metal: 0.3, rough: 0.5)
        let teal = mat(NSColor(red: 0.05, green: 0.62, blue: 0.58, alpha: 1), metal: 0.1, rough: 0.4)

        // Z lead screws (back corners) and X-axis rods
        for sx: CGFloat in [-1, 1] { rod(0.05, 3.2, at: SCNVector3(sx * 1.72, 2.15, -1.55), axis: "y", metal) }
        rod(0.045, 3.45, at: SCNVector3(0, 3.1, -0.15), axis: "x", metal)
        rod(0.045, 3.45, at: SCNVector3(0, 2.86, -0.15), axis: "x", metal)

        // Heated bed: Y rails, carriage, build plate
        for sx: CGFloat in [-1, 1] { rod(0.04, 3.3, at: SCNVector3(sx * 1.05, 0.85, 0), axis: "z", metal) }
        box(2.75, 0.12, 2.75, at: SCNVector3(0, 1.0, 0), chamfer: 0.02, dark)
        box(2.55, 0.05, 2.55, at: SCNVector3(0, 1.145, 0), chamfer: 0.01, bedMat)

        // Print in progress
        let pg = SCNBox(width: 0.55, height: 0.5, length: 0.55, chamferRadius: 0.02); pg.materials = [teal]
        part.geometry = pg; part.position = SCNVector3(0.1, 1.42, 0); scene.rootNode.addChildNode(part)

        // Toolhead
        let head = SCNNode(); head.position = SCNVector3(0.1, 2.8, 0)
        scene.rootNode.addChildNode(head)
        box(0.6, 0.42, 0.5, at: SCNVector3(0, 0, 0), chamfer: 0.04, dark, in: head)
        let ring = SCNTorus(ringRadius: 0.13, pipeRadius: 0.025); ring.materials = [teal]
        let rn = SCNNode(geometry: ring); rn.position = SCNVector3(0, 0, 0.26); rn.eulerAngles.x = .pi / 2
        head.addChildNode(rn)
        box(0.2, 0.16, 0.2, at: SCNVector3(0, -0.29, 0), chamfer: 0.01, metal, in: head)
        let cone = SCNCone(topRadius: 0.07, bottomRadius: 0.01, height: 0.14); cone.materials = [nozzleMat]
        let cn = SCNNode(geometry: cone); cn.position = SCNVector3(0, -0.44, 0)
        head.addChildNode(cn)
    }

    private func buildLights() {
        let o = SCNLight(); o.type = .omni
        o.color = NSColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        o.attenuationStartDistance = 1; o.attenuationEndDistance = 7; o.attenuationFalloffExponent = 1
        omni.light = o; omni.position = SCNVector3(0, 3.5, 0.4)
        scene.rootNode.addChildNode(omni)

        let key = SCNLight(); key.type = .directional; key.intensity = 850
        key.color = NSColor(white: 1, alpha: 1)
        let kn = SCNNode(); kn.light = key; kn.eulerAngles = SCNVector3(-0.7, 0.9, 0)
        scene.rootNode.addChildNode(kn)

        let fill = SCNLight(); fill.type = .ambient; fill.intensity = 220
        fill.color = NSColor(red: 0.75, green: 0.82, blue: 1, alpha: 1)
        let fn = SCNNode(); fn.light = fill
        scene.rootNode.addChildNode(fn)

        let rim = SCNLight(); rim.type = .directional; rim.intensity = 450
        let rn = SCNNode(); rn.light = rim; rn.eulerAngles = SCNVector3(-0.4, -2.4, 0)
        scene.rootNode.addChildNode(rn)
    }

    private func buildGround() {
        let size = CGSize(width: 256, height: 256)
        let img = NSImage(size: size, flipped: false) { r in
            NSGradient(colors: [NSColor(white: 0, alpha: 0.55), NSColor(white: 0, alpha: 0)])!
                .draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: .zero)
            return true
        }
        let plane = SCNPlane(width: 5.0, height: 5.0)
        let m = SCNMaterial(); m.lightingModel = .constant
        m.diffuse.contents = img; m.writesToDepthBuffer = false; m.isDoubleSided = true
        plane.materials = [m]
        let n = SCNNode(geometry: plane); n.eulerAngles.x = -.pi / 2; n.position = SCNVector3(0, -0.01, 0)
        n.renderingOrder = -1
        scene.rootNode.addChildNode(n)
    }

    /// Simple studio environment (equirect): bright overhead softbox, dark floor — gives the glass something to reflect.
    private static func studioImage() -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 512), flipped: false) { r in
            NSGradient(colors: [NSColor(white: 0.55, alpha: 1), NSColor(white: 0.20, alpha: 1), NSColor(white: 0.06, alpha: 1)],
                       atLocations: [0, 0.5, 1], colorSpace: .deviceGray)!.draw(in: r, angle: -90)
            NSColor(white: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 300, y: 330, width: 260, height: 110), xRadius: 20, yRadius: 20).fill()
            NSBezierPath(roundedRect: NSRect(x: 700, y: 250, width: 90, height: 160), xRadius: 14, yRadius: 14).fill()
            return true
        }
    }
}
