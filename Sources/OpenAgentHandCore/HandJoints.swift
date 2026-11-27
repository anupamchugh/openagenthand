import CoreGraphics
import Foundation
import Vision

/// Vision's 21 hand joints in one image, in an aspect-corrected plane:
/// x runs 0...aspect, y runs 0...1, origin at the lower left (Vision's convention).
public struct HandJoints: Equatable, Sendable {
    public enum Name: String, CaseIterable, Sendable {
        case wrist
        case thumbCMC, thumbMP, thumbIP, thumbTip
        case indexMCP, indexPIP, indexDIP, indexTip
        case middleMCP, middlePIP, middleDIP, middleTip
        case ringMCP, ringPIP, ringDIP, ringTip
        case littleMCP, littlePIP, littleDIP, littleTip
    }

    public var points: [Name: CGPoint]
    /// Vision's confidence (0...1) for each joint in `points`, when the source reported one.
    public var confidences: [Name: Float]
    /// Vision's handedness guess, if it made one ("left" or "right").
    public var chirality: String?
    /// Image width over height, so distances are in one unit on both axes.
    public var aspect: CGFloat

    public init(points: [Name: CGPoint], confidences: [Name: Float] = [:], chirality: String?, aspect: CGFloat) {
        self.points = points
        self.confidences = confidences
        self.chirality = chirality
        self.aspect = aspect
    }

    public subscript(name: Name) -> CGPoint? { points[name] }

    /// The point in the image's own normalized space (0...1 on both axes, lower-left origin).
    public func normalized(_ name: Name) -> CGPoint? {
        points[name].map { CGPoint(x: $0.x / aspect, y: $0.y) }
    }

    /// At least 15 of the 21 joints were seen with confidence. Vision sometimes adds a faint second
    /// "hand" made of a few joints; gestures ignore those.
    public var isReliable: Bool { points.count >= 15 }

    /// Midway between the wrist and the middle-finger knuckle.
    public var palmCentre: CGPoint? {
        guard let wrist = self[.wrist], let knuckle = self[.middleMCP] else { return nil }
        return CGPoint(x: (wrist.x + knuckle.x) / 2, y: (wrist.y + knuckle.y) / 2)
    }

    public var palmLength: CGFloat? {
        guard let wrist = self[.wrist], let knuckle = self[.middleMCP] else { return nil }
        return hypot(wrist.x - knuckle.x, wrist.y - knuckle.y)
    }

    public func transformed(_ move: (CGPoint) -> CGPoint) -> HandJoints {
        HandJoints(points: points.mapValues(move), confidences: confidences, chirality: chirality, aspect: aspect)
    }
}

extension HandJoints {
    static let visionNames: [VNHumanHandPoseObservation.JointName: Name] = [
        .wrist: .wrist,
        .thumbCMC: .thumbCMC, .thumbMP: .thumbMP, .thumbIP: .thumbIP, .thumbTip: .thumbTip,
        .indexMCP: .indexMCP, .indexPIP: .indexPIP, .indexDIP: .indexDIP, .indexTip: .indexTip,
        .middleMCP: .middleMCP, .middlePIP: .middlePIP, .middleDIP: .middleDIP, .middleTip: .middleTip,
        .ringMCP: .ringMCP, .ringPIP: .ringPIP, .ringDIP: .ringDIP, .ringTip: .ringTip,
        .littleMCP: .littleMCP, .littlePIP: .littlePIP, .littleDIP: .littleDIP, .littleTip: .littleTip,
    ]

    /// Joints Vision reports with at least `minimumConfidence`.
    public init(_ observation: VNHumanHandPoseObservation, aspect: CGFloat, minimumConfidence: Float = 0.3) {
        var points: [Name: CGPoint] = [:]
        var confidences: [Name: Float] = [:]
        let recognized = (try? observation.recognizedPoints(.all)) ?? [:]
        for (jointName, point) in recognized where point.confidence >= minimumConfidence {
            guard let name = Self.visionNames[jointName] else { continue }
            points[name] = CGPoint(x: point.location.x * aspect, y: point.location.y)
            confidences[name] = point.confidence
        }
        let chirality: String? = switch observation.chirality {
        case .left: "left"
        case .right: "right"
        default: nil
        }
        self.init(points: points, confidences: confidences, chirality: chirality, aspect: aspect)
    }

    /// One hand as `Tools/record_joints.swift` writes it: joint name → [x, y, confidence],
    /// in Vision's normalized lower-left space.
    public init(recordedJoints joints: [String: [Double]], chirality: String?, aspect: CGFloat) {
        var points: [Name: CGPoint] = [:]
        var confidences: [Name: Float] = [:]
        for (key, value) in joints where value.count == 3 && value[2] >= 0.3 {
            guard let name = Name(rawValue: key) else { continue }
            points[name] = CGPoint(x: value[0] * aspect, y: value[1])
            confidences[name] = Float(value[2])
        }
        self.init(points: points, confidences: confidences, chirality: chirality, aspect: aspect)
    }

    /// A `<sample>.joints.json` file that `Tools/record_joints.swift` wrote on a Mac.
    public init(recorded data: Data, aspect: CGFloat) throws {
        struct Recorded: Decodable {
            var chirality: String?
            var joints: [String: [Double]]
        }
        let recorded = try JSONDecoder().decode(Recorded.self, from: data)
        self.init(recordedJoints: recorded.joints, chirality: recorded.chirality, aspect: aspect)
    }
}
