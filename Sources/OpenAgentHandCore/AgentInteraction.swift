import CoreGraphics
import Foundation

public enum Agent: String, Codable, CaseIterable, Identifiable, Sendable {
    case coordinator, researcher, builder, reviewer, tester

    public var id: Self { self }

    public var finger: String {
        switch self {
        case .coordinator: "Thumb"
        case .researcher: "Index"
        case .builder: "Middle"
        case .reviewer: "Ring"
        case .tester: "Little"
        }
    }

    fileprivate var curl: WritableKeyPath<HandPose, Double> {
        switch self {
        case .coordinator: \.thumb
        case .researcher: \.index
        case .builder: \.middle
        case .reviewer: \.ring
        case .tester: \.little
        }
    }
}

public struct AgentEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case working, waiting, done, failed

        var curl: Double {
            switch self {
            case .working: 0.50
            case .waiting: 0.73
            case .done: 0.13
            case .failed: 0.98
            }
        }
    }

    public let id: Int
    public let agent: Agent
    public let phase: Phase
    public let detail: String

    public init(id: Int, agent: Agent, phase: Phase, detail: String) {
        self.id = id
        self.agent = agent
        self.phase = phase
        self.detail = detail
    }
}

public struct AgentSnapshot: Codable, Equatable, Sendable {
    public let runID: UUID
    public let events: [AgentEvent]

    public init(runID: UUID = UUID(), events: [AgentEvent] = []) {
        self.runID = runID
        self.events = events
    }

    public var isValid: Bool {
        events.count <= 200 && events.allSatisfy { $0.id > 0 && $0.detail.count <= 100 }
            && zip(events, events.dropFirst()).allSatisfy { $0.id < $1.id }
    }

    public func latest(for agent: Agent, through count: Int) -> AgentEvent? {
        events.prefix(max(0, count)).last { $0.agent == agent }
    }

    public func pose(through count: Int) -> HandPose {
        var pose = HandPose.open
        for event in events.prefix(max(0, count)) {
            pose[keyPath: event.agent.curl] = event.phase.curl
        }
        return pose
    }
}

/// A held contact selects one finger. Brief, ambiguous and repeated contacts are ignored.
public struct PinchRecognizer: Sendable {
    private static let fingers: [(Agent, HandJoints.Name)] = [
        (.researcher, .indexTip), (.builder, .middleTip), (.reviewer, .ringTip), (.tester, .littleTip),
    ]
    private var candidate: Agent?
    private var candidateSince: TimeInterval = 0
    private var releasedSince: TimeInterval?
    private var lastFrame: TimeInterval?
    private var armed = false

    public init() {}

    public static func canTrack(_ hand: HandJoints) -> Bool {
        guard let palm = hand.palmLength, palm > 0.02, hand[.thumbTip] != nil else { return false }
        return fingers.count { hand[$0.1] != nil } >= 2
    }

    public mutating func update(_ hand: HandJoints?, at time: TimeInterval) -> Agent? {
        if let lastFrame, time <= lastFrame || time - lastFrame > 0.25 {
            self = Self()
        }
        lastFrame = time
        guard let hand, Self.canTrack(hand), let palm = hand.palmLength, let thumb = hand[.thumbTip] else {
            self = Self()
            return nil
        }
        let distances = Self.fingers.compactMap { agent, joint in
            hand[joint].map { (agent, hypot(thumb.x - $0.x, thumb.y - $0.y) / palm) }
        }.sorted { $0.1 < $1.1 }
        let (nearest, distance) = distances[0]
        if distance > 0.30 {
            candidate = nil
            if releasedSince == nil { releasedSince = time }
            if let releasedSince, time - releasedSince >= 0.12 { armed = true }
            return nil
        }
        releasedSince = nil
        guard armed, distance < 0.18, distances[1].1 > 0.25 else {
            candidate = nil
            return nil
        }
        if candidate != nearest {
            candidate = nearest
            candidateSince = time
            return nil
        }
        guard time - candidateSince >= 0.18 else { return nil }
        candidate = nil
        armed = false
        return nearest
    }
}
