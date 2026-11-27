import RealityKit
import simd
import OpenAgentHandCore

/// Moves the Shadow Hand model's finger links to match a `HandPose`.
///
/// Link names, joint axes and ranges come from MuJoCo Menagerie's `shadow_hand/right_hand.xml`
/// (commit b065505). Axes are in each link's own frame, which the USDZ keeps.
@MainActor
final class HandRig {
    struct Joint {
        let link: String
        let axis: SIMD3<Float>
        /// Angle in radians at curl 1; curl 0 is the model's rest pose.
        let fullCurl: Float
    }

    static let fingerJoints: [WritableKeyPath<HandPose, Double>: [Joint]] = {
        func finger(_ prefix: String) -> [Joint] {
            [
                Joint(link: "rh_\(prefix)proximal", axis: [1, 0, 0], fullCurl: 1.45),  // J3, range -0.26...1.57
                Joint(link: "rh_\(prefix)middle", axis: [1, 0, 0], fullCurl: 1.4),     // J2, range 0...1.57
                Joint(link: "rh_\(prefix)distal", axis: [1, 0, 0], fullCurl: 1.0),     // J1, range 0...1.57
            ]
        }
        return [
            \.index: finger("ff"),
            \.middle: finger("mf"),
            \.ring: finger("rf"),
            \.little: finger("lf"),
            \.thumb: [
                Joint(link: "rh_thbase", axis: [0, 0, -1], fullCurl: 0.9),      // THJ5, range -1.05...1.05
                Joint(link: "rh_thproximal", axis: [1, 0, 0], fullCurl: 1.1),   // THJ4, range 0...1.22
                Joint(link: "rh_thmiddle", axis: [0, -1, 0], fullCurl: 0.5),    // THJ2, range -0.70...0.70
                Joint(link: "rh_thdistal", axis: [1, 0, 0], fullCurl: 1.2),     // THJ1, range -0.26...1.57
            ],
        ]
    }()

    let root: Entity
    private var links: [String: (entity: Entity, rest: Transform)] = [:]

    init(root: Entity) {
        self.root = root
        for joint in Self.fingerJoints.values.joined() {
            guard let entity = root.findEntity(named: joint.link) else { continue }
            links[joint.link] = (entity, entity.transform)
        }
    }

    /// Link names the model was expected to have but doesn't.
    var missingLinks: [String] {
        Self.fingerJoints.values.joined().map(\.link).filter { links[$0] == nil }.sorted()
    }

    func apply(_ pose: HandPose, animated: Bool = true) {
        for (digit, joints) in Self.fingerJoints {
            let curl = Float(pose[keyPath: digit])
            for joint in joints {
                guard let link = links[joint.link] else { continue }
                var transform = link.rest
                transform.rotation = link.rest.rotation * simd_quatf(angle: joint.fullCurl * curl, axis: joint.axis)
                if animated {
                    link.entity.move(to: transform, relativeTo: link.entity.parent, duration: 0.25, timingFunction: .easeInOut)
                } else {
                    link.entity.transform = transform
                }
            }
        }
    }

    static func load() async throws -> HandRig {
        let model = try await Entity(named: "ShadowHand")
        // Each view drives its own copy. With two robot hands on screen (First Contact and Mirror)
        // sharing links, both rigs animated the same fingers and on device they streaked off-screen.
        return HandRig(root: model.clone(recursive: true))
    }
}
