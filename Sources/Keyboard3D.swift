import SceneKit
import SwiftUI

/// The F99 in 3D: keycaps with their legends on a white case, lit the same
/// way as the flat picture. Drag to turn it, scroll or pinch to zoom,
/// double-click to put it back.
///
/// SceneKit only redraws when something changes, and the lights are updated
/// 20 times a second only while the window is in front and something moves.
struct Keyboard3D: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeNSView(context: Context) -> KeyboardSceneView {
        let view = KeyboardSceneView(frame: .zero, options: nil)
        view.model = model
        return view
    }

    func updateNSView(_ view: KeyboardSceneView, context: Context) {
        view.model = model
        view.refresh()
    }

    static func dismantleNSView(_ view: KeyboardSceneView, coordinator: ()) {
        view.stop()
    }
}

final class KeyboardSceneView: SCNView {
    weak var model: AppModel?
    private var caps: [(key: F99.Key, top: SCNMaterial, side: SCNMaterial, glow: SCNMaterial)] = []
    private var strip: SCNMaterial?
    private var stripOutline: SCNNode?
    private var timer: Timer?
    private var home = SCNMatrix4Identity

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        allowsCameraControl = true
        defaultCameraController.interactionMode = .orbitTurntable
        defaultCameraController.inertiaEnabled = true
        defaultCameraController.minimumVerticalAngle = -10
        defaultCameraController.maximumVerticalAngle = 89
        scene = makeScene()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func stop() { timer?.invalidate(); timer = nil }

    /// Scroll to zoom, like the flat picture's neighbours in other apps.
    override func scrollWheel(with event: NSEvent) {
        guard let camera = pointOfView else { return }
        let step = Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.04 : 0.6)
        let forward = camera.simdWorldFront
        let next = camera.simdWorldPosition + forward * step
        // Stay between close up and far away.
        let distance = simd_length(next)
        if distance > 6 && distance < 45 { camera.simdWorldPosition = next }
    }

    private var downAt: NSPoint?

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
        if event.clickCount == 2 {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            pointOfView?.transform = home
            SCNTransaction.commit()
            defaultCameraController.target = SCNVector3Zero
            return
        }
        super.mouseDown(with: event)
    }

    /// A click that didn't turn the board picks a key or the light bar,
    /// like the flat picture.
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.clickCount == 1, let downAt, let model,
              hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y) < 4 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let name = hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first?.node.name
        let hit: PictureHit? = if name == "light" { .light }
            else if let name, name.hasPrefix("key:"), let led = Int(name.dropFirst(4)) { .key(led) }
            else { nil }
        let flags = event.modifierFlags
        model.clickPicture(hit, adding: flags.contains(.command) || flags.contains(.shift))
    }

    /// Redraw now (a new mood was picked) rather than on the next tick.
    func refresh() { update(force: true) }

    private var lastStill = false
    private func tick() {
        guard let window, window.isVisible, NSApp.isActive else { return }
        update(force: false)
    }

    private func update(force: Bool) {
        guard let model else { return }
        let still = model.pictureIsStill
        // A still picture only needs drawing once.
        if still && lastStill && !force { return }
        lastStill = still
        let picked = model.selectedKeys
        let t = Date().timeIntervalSinceReferenceDate
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        for cap in caps {
            let light = model.light(for: cap.key, time: t)
            let a = max(light.r, light.g, light.b)
            let base = Theme.cap(for: cap.key.name)
            let lit = a > 0.01 ? RGB(light.r / a, light.g / a, light.b / a) : base
            let face = base.lerp(lit, 0.35 * a)
            cap.top.multiply.contents = face.nsColor
            cap.side.diffuse.contents = RGB(face.r * 0.86, face.g * 0.86, face.b * 0.9).nsColor
            cap.glow.diffuse.contents = lit.nsColor
            cap.glow.transparency = 0.75 * a
            cap.side.emission.contents = picked.contains(cap.key.led) ? Theme.pickedNS : NSColor.black
        }
        if let strip {
            let c = model.pictureStripColor.map { RGB($0.rgb.0, $0.rgb.1, $0.rgb.2) } ?? RGB(0.85, 0.85, 0.88)
            strip.diffuse.contents = c.nsColor
            stripOutline?.isHidden = model.inspecting != .light
        }
        SCNTransaction.commit()
    }

    // MARK: Building the keyboard

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let unit = F99.unit
        let boardW = F99.boardSize.w / unit, boardD = F99.boardSize.h / unit

        // White case with a lavender-grey plate on top.
        // A thin rim round the keys, a little deeper at the front, like the F99.
        let body = SCNBox(width: boardW + 0.85, height: 0.7, length: boardD + 0.95, chamferRadius: 0.22)
        body.firstMaterial = Self.matte(NSColor(red: 0.95, green: 0.95, blue: 0.98, alpha: 1))
        let caseNode = SCNNode(geometry: body)
        caseNode.position = SCNVector3(0, -0.35, 0.05)
        scene.rootNode.addChildNode(caseNode)

        let plate = SCNBox(width: boardW + 0.2, height: 0.04, length: boardD + 0.2, chamferRadius: 0.08)
        plate.firstMaterial = Self.matte(NSColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1))
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(0, 0.02, 0)
        scene.rootNode.addChildNode(plateNode)

        for key in F99.keys {
            let f = key.frame
            let w = f.w / unit, d = f.h / unit
            let x = (f.x + f.w / 2) / unit - boardW / 2
            let z = (f.y + f.h / 2) / unit - boardD / 2

            // Light spilling onto the plate around the key.
            let pad = SCNPlane(width: w + 0.3, height: d + 0.3)
            pad.cornerRadius = 0.18
            let glow = SCNMaterial()
            glow.lightingModel = .constant
            glow.writesToDepthBuffer = false
            glow.transparency = 0
            pad.firstMaterial = glow
            let padNode = SCNNode(geometry: pad)
            padNode.eulerAngles.x = -.pi / 2
            padNode.position = SCNVector3(x, 0.045, z)
            scene.rootNode.addChildNode(padNode)

            // The keycap: a wide base and a smaller top tilted towards you,
            // like a real sculpted cap. Legend on top, plain sides.
            let side = Self.matte(.white)
            let top = Self.matte(.white)
            top.diffuse.contents = Self.legendImage(for: key, width: w, depth: d)
            let base = SCNBox(width: w - 0.05, height: 0.28, length: d - 0.05, chamferRadius: 0.05)
            base.firstMaterial = side
            let baseNode = SCNNode(geometry: base)
            baseNode.name = "key:\(key.led)"
            baseNode.position = SCNVector3(x, 0.04 + 0.14, z)
            scene.rootNode.addChildNode(baseNode)
            let crown = SCNBox(width: w - 0.24, height: 0.16, length: d - 0.3, chamferRadius: 0.06)
            // front, right, back, left, top, bottom
            crown.materials = [side, side, side, side, top, side]
            let crownNode = SCNNode(geometry: crown)
            crownNode.name = "key:\(key.led)"
            crownNode.position = SCNVector3(x, 0.04 + 0.28 + 0.08, z - 0.04)
            scene.rootNode.addChildNode(crownNode)
            caps.append((key, top, side, glow))
        }

        // The light strip: a thin slot right of Backspace and Delete.
        do {
            let f = F99.stripFrame
            let bar = SCNBox(width: f.w / unit, height: 0.22, length: f.h / unit, chamferRadius: 0.03)
            let material = SCNMaterial()
            material.lightingModel = .constant
            bar.firstMaterial = material
            strip = material
            let node = SCNNode(geometry: bar)
            node.name = "light"
            node.position = SCNVector3((f.x + f.w / 2) / unit - boardW / 2, 0.13, (f.y + f.h / 2) / unit - boardD / 2)
            scene.rootNode.addChildNode(node)
            // A lavender ring round it while its panel is open.
            let ring = SCNBox(width: f.w / unit + 0.18, height: 0.16, length: f.h / unit + 0.18, chamferRadius: 0.08)
            let lavender = SCNMaterial()
            lavender.lightingModel = .constant
            lavender.diffuse.contents = Theme.pickedNS
            ring.firstMaterial = lavender
            let outline = SCNNode(geometry: ring)
            outline.position = SCNVector3(node.position.x, 0.08, node.position.z)
            outline.isHidden = true
            scene.rootNode.addChildNode(outline)
            stripOutline = outline
        }

        // Soft light from above and in front, plus a little all round.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 550
        sun.eulerAngles = SCNVector3(-1.0, 0.25, 0)
        scene.rootNode.addChildNode(sun)

        // Seen from in front, above and a little to the left, like the
        // product photos.
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 28
        camera.position = SCNVector3(-3.5, 15, 15.5)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        pointOfView = camera
        home = camera.transform
        return scene
    }

    private static func matte(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        return m
    }

    /// The top of a keycap: white with the key's legend in the corner. The
    /// light colour is multiplied in, so dark letters stay dark.
    private static func legendImage(for key: F99.Key, width: Double, depth: Double) -> NSImage {
        let px = 96.0
        let size = NSSize(width: width * px, height: depth * px)
        return NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            let options = KeyboardPicture.labels(key.name)
            guard !options.isEmpty else { return true }
            let inset = 12.0
            let room = rect.width - 2 * inset
            let color = NSColor(red: 0.30, green: 0.28, blue: 0.42, alpha: 0.9)
            func text(_ s: String, _ pt: Double) -> NSAttributedString {
                NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: pt, weight: .medium),
                                                           .foregroundColor: color])
            }
            var pt = 24.0
            var chosen = options.first { text($0, pt).size().width <= room }
            if chosen == nil, let shortest = options.last {
                pt = max(12, pt * room / max(1, text(shortest, pt).size().width))
                chosen = shortest
            }
            text(chosen ?? "", pt).draw(at: NSPoint(x: inset, y: inset))
            return true
        }
    }
}

extension RGB {
    var nsColor: NSColor { NSColor(red: r, green: g, blue: b, alpha: 1) }
}
