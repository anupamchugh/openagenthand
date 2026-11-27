import CoreGraphics
import Testing
@testable import OpenAgentHandCore

struct AgentInteractionTests {
    @Test func relayOnlyMovesTheFingerForEachAgent() {
        let snapshot = AgentSnapshot(events: [
            AgentEvent(id: 1, agent: .researcher, phase: .working, detail: "Reading"),
            AgentEvent(id: 2, agent: .reviewer, phase: .waiting, detail: "Waiting"),
            AgentEvent(id: 3, agent: .researcher, phase: .done, detail: "Read"),
        ])
        #expect(snapshot.isValid)
        #expect(snapshot.pose(through: 1).ring == 0)
        #expect(snapshot.pose(through: 2).index == 0.5)
        #expect(snapshot.pose(through: 3).index == 0.13)
        #expect(snapshot.pose(through: 3).ring == 0.73)
        #expect(snapshot.latest(for: .reviewer, through: 1) == nil)
        #expect(!AgentSnapshot(events: snapshot.events.reversed()).isValid)
    }

    @Test(arguments: [Agent.researcher, .builder, .reviewer, .tester])
    func heldPinchSelectsOnceAndRequiresRelease(agent: Agent) {
        var recognizer = PinchRecognizer()
        let open = joints(thumbX: 0.05, thumbY: 0.4)
        let pinch = joints(thumbX: positions[agent] ?? 0, thumbY: 0.8)
        #expect(recognizer.update(pinch, at: 0) == nil)
        _ = recognizer.update(open, at: 0.08)
        _ = recognizer.update(open, at: 0.22)
        #expect(recognizer.update(pinch, at: 0.27) == nil)
        #expect(recognizer.update(pinch, at: 0.37) == nil)
        #expect(recognizer.update(pinch, at: 0.48) == agent)
        #expect(recognizer.update(pinch, at: 0.67) == nil)
    }

    @Test func twoNearbyFingersAndMissingJointsCannotTriggerAnIntent() {
        var recognizer = PinchRecognizer()
        let open = joints(thumbX: 0.05, thumbY: 0.4)
        let ambiguous = joints(thumbX: 0.50, thumbY: 0.8)
        let ring = joints(thumbX: 0.58, thumbY: 0.8)
        _ = recognizer.update(open, at: 0)
        _ = recognizer.update(open, at: 0.14)
        _ = recognizer.update(ambiguous, at: 0.19)
        #expect(recognizer.update(ambiguous, at: 0.39) == nil)
        _ = recognizer.update(ring, at: 0.45)
        _ = recognizer.update(nil, at: 0.50)
        _ = recognizer.update(ring, at: 0.58)
        #expect(recognizer.update(ring, at: 0.80) == nil)
    }

    private let positions: [Agent: CGFloat] = [.researcher: 0.15, .builder: 0.4, .reviewer: 0.58, .tester: 0.83]

    private func joints(thumbX: CGFloat, thumbY: CGFloat) -> HandJoints {
        HandJoints(points: [
            .wrist: CGPoint(x: 0.4, y: 0.15),
            .middleMCP: CGPoint(x: 0.4, y: 0.65),
            .thumbTip: CGPoint(x: thumbX, y: thumbY),
            .indexTip: CGPoint(x: 0.15, y: 0.8),
            .middleTip: CGPoint(x: 0.4, y: 0.8),
            .ringTip: CGPoint(x: 0.58, y: 0.8),
            .littleTip: CGPoint(x: 0.83, y: 0.8),
        ], chirality: nil, aspect: 1)
    }
}
