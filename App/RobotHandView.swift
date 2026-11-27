import RealityKit
import SwiftUI
import OpenAgentHandCore

/// The Shadow Hand in a lit, non-AR RealityKit scene, posed by `pose`.
struct RobotHandView: View {
    var pose: HandPose

    @State private var rig: HandRig?
    @State private var loadError: String?

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            guard let rig = try? await HandRig.load() else {
                loadError = "Couldn't load ShadowHand.usdz"
                return
            }
            content.add(Self.stage(for: rig).root)
            rig.apply(pose, animated: false)
            self.rig = rig
        } update: { _ in
            // Camera frames arrive faster than a 0.25 s RealityKit animation can finish.
            // Apply each target directly so overlapping animations cannot corrupt the rig.
            rig?.apply(pose, animated: false)
        }
        .overlay {
            if let loadError {
                ContentUnavailableView(loadError, systemImage: "hand.raised.slash")
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Robot hand")
        .accessibilityValue(HandShape(pose)?.rawValue ?? "In between gestures")
    }
}

extension RobotHandView {
    /// Turns the upright hand about its length so the palm faces the viewer.
    private static let palmTurn: Float = .pi / 2

    /// The rig stood upright and framed, with its camera and light. The live view and the
    /// replay renderer both use this, so a replay looks like the screen.
    @MainActor
    static func stage(for rig: HandRig) -> (root: Entity, camera: PerspectiveCamera) {
        // The Menagerie forearm lays the hand along +X: turn the fingers up,
        // then scale and centre the whole arm to fill the view.
        let stand = Entity()
        stand.orientation = simd_quatf(angle: palmTurn, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        stand.addChild(rig.root)
        // Frame the palm and fingers; the forearm runs off the bottom.
        let bounds = (rig.root.findEntity(named: "rh_palm") ?? stand).visualBounds(relativeTo: nil)
        let scale = 0.26 / max(bounds.extents.y, 0.001)
        stand.scale = [scale, scale, scale]
        stand.position = -bounds.center * scale + [0, -0.02, 0]

        let anchor = Entity()
        anchor.addChild(stand)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 40
        camera.look(at: .zero, from: [0, 0, 0.5], relativeTo: nil)
        anchor.addChild(camera)
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.look(at: .zero, from: [0.4, 0.6, 1], relativeTo: nil)
        anchor.addChild(light)
        return (anchor, camera)
    }
}
