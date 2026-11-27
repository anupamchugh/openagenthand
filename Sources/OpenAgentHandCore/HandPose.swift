import CoreGraphics

/// How far each finger is bent, 0 (straight) to 1 (fully curled).
public struct HandPose: Equatable, Sendable {
    public var thumb: Double
    public var index: Double
    public var middle: Double
    public var ring: Double
    public var little: Double

    public init(thumb: Double, index: Double, middle: Double, ring: Double, little: Double) {
        self.thumb = thumb
        self.index = index
        self.middle = middle
        self.ring = ring
        self.little = little
    }

    public static let open = HandPose(thumb: 0, index: 0, middle: 0, ring: 0, little: 0)
}

extension HandPose {
    /// Reads bend from 2D joints by how close each fingertip sits to the palm.
    ///
    /// A straight finger's tip is about twice as far from the wrist as its knuckle (MCP);
    /// a curled one is about as far. The thumb is measured against the little-finger knuckle,
    /// scaled by the knuckle row's width. Calibrated on Mirror Hand's three sample photos.
    /// Returns nil when Vision missed a joint it needs.
    public init?(_ joints: HandJoints) {
        func distance(_ a: HandJoints.Name, _ b: HandJoints.Name) -> Double? {
            guard let p = joints[a], let q = joints[b] else { return nil }
            return hypot(p.x - q.x, p.y - q.y)
        }
        func curl(ratio: Double, straight: Double, curled: Double) -> Double {
            min(max((straight - ratio) / (straight - curled), 0), 1)
        }
        func finger(tip: HandJoints.Name, mcp: HandJoints.Name) -> Double? {
            guard let reach = distance(.wrist, tip), let base = distance(.wrist, mcp), base > 0 else { return nil }
            return curl(ratio: reach / base, straight: 1.8, curled: 1.0)
        }
        guard
            let index = finger(tip: .indexTip, mcp: .indexMCP),
            let middle = finger(tip: .middleTip, mcp: .middleMCP),
            let ring = finger(tip: .ringTip, mcp: .ringMCP),
            let little = finger(tip: .littleTip, mcp: .littleMCP),
            let thumbReach = distance(.thumbTip, .littleMCP),
            let knuckles = distance(.indexMCP, .littleMCP), knuckles > 0
        else { return nil }
        let thumb = curl(ratio: thumbReach / knuckles, straight: 1.9, curled: 0.7)
        self.init(thumb: thumb, index: index, middle: middle, ring: ring, little: little)
    }
}

/// A still hand shape, read from which digits are straight.
public enum HandShape: String, CaseIterable, Sendable {
    case openPalm
    case fist
    case thumbsUp
    case point
    case peace
    /// Thumb, index and little finger up: the sign for "I love you".
    case loveYou

    /// Which digits are straight, thumb first.
    private var extended: (thumb: Bool, index: Bool, middle: Bool, ring: Bool, little: Bool) {
        switch self {
        case .openPalm: (true, true, true, true, true)
        case .fist: (false, false, false, false, false)
        case .thumbsUp: (true, false, false, false, false)
        case .point: (false, true, false, false, false)
        case .peace: (false, true, true, false, false)
        case .loveYou: (true, true, false, false, true)
        }
    }

    /// The idealised pose for this shape.
    public var pose: HandPose {
        let e = extended
        func curl(_ straight: Bool) -> Double { straight ? 0 : 1 }
        return HandPose(thumb: curl(e.thumb), index: curl(e.index), middle: curl(e.middle), ring: curl(e.ring), little: curl(e.little))
    }

    /// The shape whose straight/bent pattern matches the pose, if any.
    public init?(_ pose: HandPose) {
        func straight(_ curl: Double) -> Bool { curl < 0.5 }
        let fingers = (straight(pose.index), straight(pose.middle), straight(pose.ring), straight(pose.little))
        let match = HandShape.allCases.first { shape in
            let e = shape.extended
            guard (e.index, e.middle, e.ring, e.little) == fingers else { return false }
            // With all four fingers bent the thumb decides fist vs thumbs up; otherwise ignore it,
            // because a tucked thumb reads loosely from a 2D image.
            return fingers != (false, false, false, false) || e.thumb == straight(pose.thumb)
        }
        guard let match else { return nil }
        self = match
    }

    /// The shape of one hand's joints, if Vision saw enough of it.
    public init?(_ joints: HandJoints) {
        guard let pose = HandPose(joints) else { return nil }
        self.init(pose)
    }
}
